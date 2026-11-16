#define _HAS_EXCEPTIONS 0
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstring>
#include <algorithm>
#include <vector>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#include "stb_image.h"

// UnityCapture DirectShow Filter Shared Memory Protocol
#define MAX_SHARED_IMAGE_SIZE (3840 * 2160 * 4 * sizeof(short))

#pragma pack(push, 1)
struct SharedMemHeader {
    DWORD maxSize;
    int width;
    int height;
    int stride;
    int format;      // 0 = FORMAT_UINT8 (BGRA32)
    int resizemode;  // 1 = RESIZEMODE_LINEAR
    int mirrormode;  // 0 = DISABLED
    int timeout;     // 1000 ms
    uint8_t data[1];
};
#pragma pack(pop)

static const char* CS_NAME_MUTEX       = "UnityCapture_Mutx";
static const char* CS_NAME_EVENT_WANT  = "UnityCapture_Want";
static const char* CS_NAME_EVENT_SENT  = "UnityCapture_Sent";
static const char* CS_NAME_SHARED_DATA = "UnityCapture_Data";

struct VirtualCameraState {
    HANDLE hMutex = NULL;
    HANDLE hWantEvent = NULL;
    HANDLE hSentEvent = NULL;
    HANDLE hMapFile = NULL;
    SharedMemHeader* pSharedBuf = NULL;
    int targetWidth = 1920;
    int targetHeight = 1080;
    int fps = 60;
    std::vector<uint8_t> processedBuffer;
};

static VirtualCameraState g_cam;

inline uint8_t ClampByte(float val) {
    if (val < 0.0f) return 0;
    if (val > 255.0f) return 255;
    return static_cast<uint8_t>(val);
}

extern "C" {

__declspec(dllexport) int InitVirtualCamera(int width, int height, int fps) {
    g_cam.targetWidth = width;
    g_cam.targetHeight = height;
    g_cam.fps = fps;
    g_cam.processedBuffer.resize(width * height * 4);

    if (!g_cam.hMutex) {
        g_cam.hMutex = CreateMutexA(NULL, FALSE, CS_NAME_MUTEX);
        if (!g_cam.hMutex) {
            g_cam.hMutex = OpenMutexA(SYNCHRONIZE, FALSE, CS_NAME_MUTEX);
        }
    }

    if (!g_cam.hWantEvent) {
        g_cam.hWantEvent = CreateEventA(NULL, FALSE, FALSE, CS_NAME_EVENT_WANT);
    }

    if (!g_cam.hSentEvent) {
        g_cam.hSentEvent = CreateEventA(NULL, FALSE, FALSE, CS_NAME_EVENT_SENT);
    }

    if (!g_cam.hMapFile) {
        DWORD totalSize = static_cast<DWORD>(sizeof(SharedMemHeader) + MAX_SHARED_IMAGE_SIZE);
        g_cam.hMapFile = CreateFileMappingA(
            INVALID_HANDLE_VALUE,
            NULL,
            PAGE_READWRITE,
            0,
            totalSize,
            CS_NAME_SHARED_DATA
        );
        if (!g_cam.hMapFile) {
            g_cam.hMapFile = OpenFileMappingA(FILE_MAP_WRITE, FALSE, CS_NAME_SHARED_DATA);
        }
    }

    if (!g_cam.hMapFile) return -1;

    g_cam.pSharedBuf = static_cast<SharedMemHeader*>(
        MapViewOfFile(g_cam.hMapFile, FILE_MAP_WRITE, 0, 0, 0)
    );

    if (!g_cam.pSharedBuf) return -2;

    if (g_cam.pSharedBuf->maxSize != MAX_SHARED_IMAGE_SIZE) {
        g_cam.pSharedBuf->maxSize = MAX_SHARED_IMAGE_SIZE;
    }

    return 0;
}

__declspec(dllexport) int SendJpegFrameWithGrading(
    const uint8_t* jpegBytes,
    int jpegSize,
    float brightness,
    float contrast,
    float saturation,
    float warmth,
    float tint,
    int flipH,
    int flipV,
    int rotation
) {
    if (!g_cam.pSharedBuf || !g_cam.hMutex || !jpegBytes || jpegSize <= 0) {
        return -1;
    }

    int imgW = 0, imgH = 0, channels = 0;
    // Decode JPEG to RGBA (4 channels)
    uint8_t* decodedRgba = stbi_load_from_memory(jpegBytes, jpegSize, &imgW, &imgH, &channels, 4);
    if (!decodedRgba) {
        return -2;
    }

    int totalPixels = imgW * imgH;
    if (static_cast<int>(g_cam.processedBuffer.size()) < totalPixels * 4) {
        g_cam.processedBuffer.resize(totalPixels * 4);
    }

    uint8_t* dst = g_cam.processedBuffer.data();

    // Fast Color Grading & Orientation transform into BGRA (DirectShow format)
    for (int y = 0; y < imgH; ++y) {
        int srcY = flipV ? (imgH - 1 - y) : y;
        for (int x = 0; x < imgW; ++x) {
            int srcX = flipH ? (imgW - 1 - x) : x;

            int srcIdx = (srcY * imgW + srcX) * 4;
            int dstIdx = (y * imgW + x) * 4;

            float r = decodedRgba[srcIdx + 0];
            float g = decodedRgba[srcIdx + 1];
            float b = decodedRgba[srcIdx + 2];

            // 1. Brightness
            r += brightness;
            g += brightness;
            b += brightness;

            // 2. Contrast
            r = (r - 128.0f) * contrast + 128.0f;
            g = (g - 128.0f) * contrast + 128.0f;
            b = (b - 128.0f) * contrast + 128.0f;

            // 3. Saturation
            float lum = 0.299f * r + 0.587f * g + 0.114f * b;
            r = lum + (r - lum) * saturation;
            g = lum + (g - lum) * saturation;
            b = lum + (b - lum) * saturation;

            // 4. Warmth & Tint
            r += warmth;
            b -= warmth;
            g += tint;

            // Write to BGRA for DirectShow
            dst[dstIdx + 0] = ClampByte(b);
            dst[dstIdx + 1] = ClampByte(g);
            dst[dstIdx + 2] = ClampByte(r);
            dst[dstIdx + 3] = 255;
        }
    }

    stbi_image_free(decodedRgba);

    // Write to UnityCapture Shared Memory
    DWORD waitResult = WaitForSingleObject(g_cam.hMutex, 5);
    if (waitResult == WAIT_OBJECT_0) {
        g_cam.pSharedBuf->width = imgW;
        g_cam.pSharedBuf->height = imgH;
        g_cam.pSharedBuf->stride = imgW * 4;
        g_cam.pSharedBuf->format = 0;      // FORMAT_UINT8 (BGRA32)
        g_cam.pSharedBuf->resizemode = 1;  // RESIZEMODE_LINEAR
        g_cam.pSharedBuf->mirrormode = 0;
        g_cam.pSharedBuf->timeout = 1000;

        memcpy(g_cam.pSharedBuf->data, dst, totalPixels * 4);

        ReleaseMutex(g_cam.hMutex);

        if (g_cam.hSentEvent) {
            SetEvent(g_cam.hSentEvent);
        }
        return 0;
    }

    return -3;
}

__declspec(dllexport) void CloseVirtualCamera() {
    if (g_cam.pSharedBuf) {
        UnmapViewOfFile(g_cam.pSharedBuf);
        g_cam.pSharedBuf = NULL;
    }
    if (g_cam.hMapFile) {
        CloseHandle(g_cam.hMapFile);
        g_cam.hMapFile = NULL;
    }
    if (g_cam.hSentEvent) {
        CloseHandle(g_cam.hSentEvent);
        g_cam.hSentEvent = NULL;
    }
    if (g_cam.hWantEvent) {
        CloseHandle(g_cam.hWantEvent);
        g_cam.hWantEvent = NULL;
    }
    if (g_cam.hMutex) {
        CloseHandle(g_cam.hMutex);
        g_cam.hMutex = NULL;
    }
}

}
