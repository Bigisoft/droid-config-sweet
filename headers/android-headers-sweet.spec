Name:       android-headers-sweet
Summary:    Android 16 headers stand-in for Xiaomi Redmi Note 10 Pro (sweet)
Version:    16.0.0
Release:    1
License:    ASL 2.0
URL:        https://github.com/Bigisoft/droid-config-sweet
Provides:   android-headers = %{version}
Provides:   pkgconfig(android-headers) = %{version}

%description
Headers-only stand-in for droid-hal-sweet-devel. The headers were extracted
with libhybris utils/extract-headers.sh (sailfishos-mirror/libhybris 02f9f62,
three Android 16 path adaptations) from a minimal ANDROID_ROOT made of
LineageOS lineage-23.2 repositories plus AOSP hardware/libhardware_legacy
android-16.0.0_r4. It is NOT droid-hal-sweet-devel: it carries no device
build output, only the generic Android headers and android-headers.pc, so that
pkgconfig(android-headers) resolves when building droid-config-sweet.

%prep
# Built in-tree by mb2 from ./headers

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_includedir}/android %{buildroot}%{_libdir}/pkgconfig
cp -a headers/. %{buildroot}%{_includedir}/android/
rm -f %{buildroot}%{_includedir}/android/android-headers.pc
install -m 0644 headers/android-headers.pc %{buildroot}%{_libdir}/pkgconfig/android-headers.pc

%files
%defattr(-,root,root,-)
%{_includedir}/android
%{_libdir}/pkgconfig/android-headers.pc
