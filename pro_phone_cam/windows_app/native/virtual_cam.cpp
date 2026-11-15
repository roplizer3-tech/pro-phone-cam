#include <windows.h>
#include <cstdint>
#include <cstring>
#include <algorithm>
#include <vector>

static const char* SHARED_MEM_NAME = "Local\\ProPhoneWebcamSharedMem";
static const char* MUTEX_NAME = "Local\\ProPhoneWebcamMutex";
static const uint32_t PPCM_MAGIC = 0x5050434D;

#pragma pack(push, 1)
struct SharedImageHeader {
    uint32_t magic;
    uint32_t width;
    uint32_t height;
    uint32_t format;
    uint32_t frameNumber;
    uint64_t timestamp;
    uint32_t dataSize;
};
#pragma pack(pop)

struct VirtualCameraState {
    HANDLE hMapFile = NULL;
    HANDLE hMutex = NULL;
    uint8_t* pBuf = NULL;
    int width = 1920;
    int height = 1080;
    int fps = 60;
    uint32_t frameCounter = 0;
    std::vector<uint8_t> processBuffer;
};

static VirtualCameraState g_camState;

inline uint8_t ClampByte(float val) {
    if (val < 0.0f) return 0;
    if (val > 255.0f) return 255;
    return static_cast<uint8_t>(val);
}

extern "C" {

__declspec(dllexport) int InitVirtualCamera(int width, int height, int fps) {
    g_camState.width = width;
    g_camState.height = height;
    g_camState.fps = fps;

    size_t totalBytes = sizeof(SharedImageHeader) + (width * height * 4);
    g_camState.processBuffer.resize(width * height * 4);

    g_camState.hMutex = CreateMutexA(NULL, FALSE, MUTEX_NAME);
    if (!g_camState.hMutex) return -1;

    g_camState.hMapFile = CreateFileMappingA(
        INVALID_HANDLE_VALUE,
        NULL,
        PAGE_READWRITE,
        0,
        static_cast<DWORD>(totalBytes),
        SHARED_MEM_NAME
    );

    if (!g_camState.hMapFile) {
        CloseHandle(g_camState.hMutex);
        g_camState.hMutex = NULL;
        return -2;
    }

    g_camState.pBuf = static_cast<uint8_t*>(MapViewOfFile(
        g_camState.hMapFile,
        FILE_MAP_ALL_ACCESS,
        0,
        0,
        totalBytes
    ));

    if (!g_camState.pBuf) {
        CloseHandle(g_camState.hMapFile);
        CloseHandle(g_camState.hMutex);
        return -3;
    }

    SharedImageHeader* header = reinterpret_cast<SharedImageHeader*>(g_camState.pBuf);
    header->magic = PPCM_MAGIC;
    header->width = width;
    header->height = height;
    header->format = 0;
    header->frameNumber = 0;
    header->timestamp = 0;
    header->dataSize = width * height * 4;

    return 0;
}

__declspec(dllexport) int SendFrameWithGrading(
    const uint8_t* rawBgra,
    int bufferSize,
    float brightness,
    float contrast,
    float saturation,
    float warmth,
    float tint,
    int flipH,
    int flipV,
    int rotation
) {
    if (!g_camState.pBuf || !g_camState.hMutex) return -1;

    int w = g_camState.width;
    int h = g_camState.height;
    int totalPixels = w * h;
    if (bufferSize < totalPixels * 4) return -2;

    uint8_t* dst = g_camState.processBuffer.data();

    for (int y = 0; y < h; ++y) {
        int srcY = flipV ? (h - 1 - y) : y;
        for (int x = 0; x < w; ++x) {
            int srcX = flipH ? (w - 1 - x) : x;

            int srcIdx = (srcY * w + srcX) * 4;
            int dstIdx = (y * w + x) * 4;

            float b = rawBgra[srcIdx + 0];
            float g = rawBgra[srcIdx + 1];
            float r = rawBgra[srcIdx + 2];
            uint8_t a = rawBgra[srcIdx + 3];

            b += brightness;
            g += brightness;
            r += brightness;

            b = (b - 128.0f) * contrast + 128.0f;
            g = (g - 128.0f) * contrast + 128.0f;
            r = (r - 128.0f) * contrast + 128.0f;

            float lum = 0.299f * r + 0.587f * g + 0.114f * b;
            b = lum + (b - lum) * saturation;
            g = lum + (g - lum) * saturation;
            r = lum + (r - lum) * saturation;

            r += warmth;
            b -= warmth;
            g += tint;

            dst[dstIdx + 0] = ClampByte(b);
            dst[dstIdx + 1] = ClampByte(g);
            dst[dstIdx + 2] = ClampByte(r);
            dst[dstIdx + 3] = a;
        }
    }

    DWORD waitResult = WaitForSingleObject(g_camState.hMutex, 5);
    if (waitResult == WAIT_OBJECT_0) {
        SharedImageHeader* header = reinterpret_cast<SharedImageHeader*>(g_camState.pBuf);
        header->frameNumber = ++g_camState.frameCounter;
        header->timestamp = GetTickCount64();

        uint8_t* frameDst = g_camState.pBuf + sizeof(SharedImageHeader);
        memcpy(frameDst, dst, totalPixels * 4);

        ReleaseMutex(g_camState.hMutex);
        return 0;
    }

    return -3;
}

__declspec(dllexport) int RegisterVirtualCameraFilter(const wchar_t* friendlyName) {
    HKEY hKey;
    const wchar_t* subKey = L"CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\{7A9B3E21-48C0-4E8F-B28A-9D1E8F2314A0}";
    
    LSTATUS status = RegCreateKeyExW(
        HKEY_CLASSES_ROOT,
        subKey,
        0,
        NULL,
        REG_OPTION_NON_VOLATILE,
        KEY_SET_VALUE,
        NULL,
        &hKey,
        NULL
    );

    if (status != ERROR_SUCCESS) return -1;

    const wchar_t* name = (friendlyName && wcslen(friendlyName) > 0) ? friendlyName : L"ProPhone Webcam";
    RegSetValueExW(hKey, L"FriendlyName", 0, REG_SZ, reinterpret_cast<const BYTE*>(name), (wcslen(name) + 1) * sizeof(wchar_t));
    
    const wchar_t* clsid = L"{7A9B3E21-48C0-4E8F-B28A-9D1E8F2314A0}";
    RegSetValueExW(hKey, L"CLSID", 0, REG_SZ, reinterpret_cast<const BYTE*>(clsid), (wcslen(clsid) + 1) * sizeof(wchar_t));

    RegCloseKey(hKey);
    return 0;
}

__declspec(dllexport) int UnregisterVirtualCameraFilter() {
    const wchar_t* subKey = L"CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\{7A9B3E21-48C0-4E8F-B28A-9D1E8F2314A0}";
    LSTATUS status = RegDeleteKeyW(HKEY_CLASSES_ROOT, subKey);
    return (status == ERROR_SUCCESS) ? 0 : -1;
}

__declspec(dllexport) void CloseVirtualCamera() {
    if (g_camState.pBuf) {
        UnmapViewOfFile(g_camState.pBuf);
        g_camState.pBuf = NULL;
    }
    if (g_camState.hMapFile) {
        CloseHandle(g_camState.hMapFile);
        g_camState.hMapFile = NULL;
    }
    if (g_camState.hMutex) {
        CloseHandle(g_camState.hMutex);
        g_camState.hMutex = NULL;
    }
}

}
