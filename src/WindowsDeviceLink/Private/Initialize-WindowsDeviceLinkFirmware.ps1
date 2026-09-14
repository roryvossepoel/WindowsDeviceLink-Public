function Initialize-WindowsDeviceLinkFirmware {
    [CmdletBinding()]
    param()

    if (-not ('WindowsDeviceLink.FirmwareNative' -as [type])) {
        Add-Type @"
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WindowsDeviceLink {
    public static class FirmwareNative {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern uint GetFirmwareEnvironmentVariable(
            string lpName,
            string lpGuid,
            byte[] pBuffer,
            uint nSize
        );

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetFirmwareEnvironmentVariable(
            string lpName,
            string lpGuid,
            byte[] pValue,
            uint nSize
        );
    }

    public static class FirmwarePrivilege {
        [StructLayout(LayoutKind.Sequential)]
        public struct LUID {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES {
            public uint PrivilegeCount;
            public LUID Luid;
            public uint Attributes;
        }

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool AdjustTokenPrivileges(
            IntPtr TokenHandle,
            bool DisableAllPrivileges,
            ref TOKEN_PRIVILEGES NewState,
            uint BufferLength,
            IntPtr PreviousState,
            IntPtr ReturnLength
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CloseHandle(IntPtr hObject);

        public static void EnableSystemEnvironmentPrivilege() {
            const uint TOKEN_ADJUST_PRIVILEGES = 0x20;
            const uint TOKEN_QUERY = 0x8;
            const uint SE_PRIVILEGE_ENABLED = 0x2;
            const int ERROR_NOT_ALL_ASSIGNED = 1300;

            IntPtr token = IntPtr.Zero;
            try {
                if (!OpenProcessToken(Process.GetCurrentProcess().Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                LUID luid;
                if (!LookupPrivilegeValue(null, "SeSystemEnvironmentPrivilege", out luid))
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1;
                tp.Luid = luid;
                tp.Attributes = SE_PRIVILEGE_ENABLED;

                if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                int error = Marshal.GetLastWin32Error();
                if (error == ERROR_NOT_ALL_ASSIGNED)
                    throw new Win32Exception(error, "SeSystemEnvironmentPrivilege is not available in the current process token.");
            }
            finally {
                if (token != IntPtr.Zero)
                    CloseHandle(token);
            }
        }
    }
}
"@ -ErrorAction Stop
    }

    try {
        [WindowsDeviceLink.FirmwarePrivilege]::EnableSystemEnvironmentPrivilege()
    }
    catch {
        throw "Unable to enable SeSystemEnvironmentPrivilege. Run from an elevated Windows PowerShell session. $($_.Exception.Message)"
    }
}
