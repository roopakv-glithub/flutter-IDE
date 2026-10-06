#pragma once

// Windows SDK 19041 uses wait_for before declaring it in its WinRT headers.
// https://github.com/microsoft/cppwinrt/issues/744
#include <windows.h>
#include <unknwn.h>
#include <winrt/base.h>

namespace winrt::impl {
template <typename Async>
auto wait_for(Async const& async,
              Windows::Foundation::TimeSpan const& timeout);
}
