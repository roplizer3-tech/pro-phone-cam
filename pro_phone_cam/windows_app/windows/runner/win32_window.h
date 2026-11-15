#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <dwmapi.h>

#include <memory>
#include <string>

// A class that abstracts the creation and management of a Win32 window.
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring& title,
              const Point& origin,
              const Size& size);

  void Show();
  void Destroy();
  void SetChildContent(HWND content);
  HWND GetNativeWindow() const;
  void SetQuitOnClose(bool quit_on_close);
  RECT GetClientArea();

 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();

  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

 private:
  friend class WindowClassRegistrar;
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
};

// Manages the registration of the window class.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar();
  static WindowClassRegistrar* GetInstance();
  const wchar_t* GetOrCreateWindowClass();

 private:
  WindowClassRegistrar();
  std::wstring class_name_;
};

#endif  // RUNNER_WIN32_WINDOW_H_
