<#
.SYNOPSIS
Read-only research probe for the DeviceLink WinRT runtime.

.DESCRIPTION
Activates ModernDeployment.Autopilot.Core.DeviceLinkUtilities through registered WinRT,
then reads IInspectable metadata only: runtime class name, trust level, and all IIDs
reported by GetIids. It also asks WindowsRuntimeMetadata to resolve the
ModernDeployment.Autopilot.Core namespace when that API is available.

This script does not call DeviceLink generation, discovery, link, firmware write,
Graph, reboot, or any other state-changing operation.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$typeName = 'WindowsDeviceLinkResearch.RuntimeInventory'
if (-not ($typeName -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WindowsDeviceLinkResearch
{
    public sealed class RuntimeInventoryResult
    {
        public string RuntimeClassName { get; set; }
        public int TrustLevel { get; set; }
        public Guid[] InterfaceIds { get; set; }
    }

    public static class RuntimeInventory
    {
        private const string RuntimeClassName = "ModernDeployment.Autopilot.Core.DeviceLinkUtilities";

        [DllImport("combase.dll")]
        private static extern int RoInitialize(uint initType);

        [DllImport("combase.dll")]
        private static extern void RoUninitialize();

        [DllImport("combase.dll")]
        private static extern int RoActivateInstance(IntPtr activatableClassId, out IntPtr instance);

        [DllImport("combase.dll", CharSet = CharSet.Unicode)]
        private static extern int WindowsCreateString(string sourceString, int length, out IntPtr hstring);

        [DllImport("combase.dll")]
        private static extern int WindowsDeleteString(IntPtr hstring);

        [DllImport("combase.dll")]
        private static extern IntPtr WindowsGetStringRawBuffer(IntPtr hstring, out uint length);

        [DllImport("ole32.dll")]
        private static extern void CoTaskMemFree(IntPtr pv);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetIidsDelegate(IntPtr self, out uint iidCount, out IntPtr iids);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetRuntimeClassNameDelegate(IntPtr self, out IntPtr className);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetTrustLevelDelegate(IntPtr self, out int trustLevel);

        public static RuntimeInventoryResult Inspect()
        {
            IntPtr className = IntPtr.Zero;
            IntPtr instance = IntPtr.Zero;
            IntPtr returnedClassName = IntPtr.Zero;
            IntPtr iidBuffer = IntPtr.Zero;
            bool uninitialize = false;

            try
            {
                int init = RoInitialize(0);
                uninitialize = init >= 0;

                ThrowIfFailed(WindowsCreateString(RuntimeClassName, RuntimeClassName.Length, out className), "WindowsCreateString");
                ThrowIfFailed(RoActivateInstance(className, out instance), "RoActivateInstance");

                var getIids = GetVtableDelegate<GetIidsDelegate>(instance, 3);
                uint count;
                ThrowIfFailed(getIids(instance, out count, out iidBuffer), "IInspectable.GetIids");

                var ids = new List<Guid>();
                int guidSize = Marshal.SizeOf(typeof(Guid));
                for (uint i = 0; i < count; i++)
                {
                    IntPtr current = IntPtr.Add(iidBuffer, checked((int)(i * guidSize)));
                    ids.Add((Guid)Marshal.PtrToStructure(current, typeof(Guid)));
                }

                var getRuntimeClassName = GetVtableDelegate<GetRuntimeClassNameDelegate>(instance, 4);
                ThrowIfFailed(getRuntimeClassName(instance, out returnedClassName), "IInspectable.GetRuntimeClassName");
                uint nameLength;
                IntPtr nameBuffer = WindowsGetStringRawBuffer(returnedClassName, out nameLength);
                string actualName = nameBuffer == IntPtr.Zero ? null : Marshal.PtrToStringUni(nameBuffer, checked((int)nameLength));

                var getTrustLevel = GetVtableDelegate<GetTrustLevelDelegate>(instance, 5);
                int trustLevel;
                ThrowIfFailed(getTrustLevel(instance, out trustLevel), "IInspectable.GetTrustLevel");

                return new RuntimeInventoryResult
                {
                    RuntimeClassName = actualName,
                    TrustLevel = trustLevel,
                    InterfaceIds = ids.ToArray()
                };
            }
            finally
            {
                if (iidBuffer != IntPtr.Zero) CoTaskMemFree(iidBuffer);
                if (returnedClassName != IntPtr.Zero) WindowsDeleteString(returnedClassName);
                if (instance != IntPtr.Zero) Marshal.Release(instance);
                if (className != IntPtr.Zero) WindowsDeleteString(className);
                if (uninitialize) RoUninitialize();
            }
        }

        private static T GetVtableDelegate<T>(IntPtr instance, int slot) where T : class
        {
            IntPtr table = Marshal.ReadIntPtr(instance);
            IntPtr method = Marshal.ReadIntPtr(table, slot * IntPtr.Size);
            return Marshal.GetDelegateForFunctionPointer(method, typeof(T)) as T;
        }

        private static void ThrowIfFailed(int hr, string operation)
        {
            if (hr < 0) throw new COMException(operation + " failed with HRESULT 0x" + hr.ToString("X8") + ".", hr);
        }
    }
}
'@
}

$native = [WindowsDeviceLinkResearch.RuntimeInventory]::Inspect()

$resolvedMetadata = @()
$metadataError = $null
try {
    $metadataType = [type]::GetType('System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeMetadata, System.Runtime.WindowsRuntime', $false)
    if ($metadataType) {
        $resolve = $metadataType.GetMethods() |
            Where-Object { $_.Name -eq 'ResolveNamespace' -and $_.GetParameters().Count -eq 2 } |
            Select-Object -First 1

        if ($resolve) {
            $result = $resolve.Invoke($null, @('ModernDeployment.Autopilot.Core', $null))
            if ($result) { $resolvedMetadata = @($result | ForEach-Object { [string]$_ }) }
        }
    }
    else {
        $metadataError = 'WindowsRuntimeMetadata type is not available in this PowerShell/.NET runtime.'
    }
}
catch {
    $metadataError = $_.Exception.Message
}

[pscustomobject]@{
    PSTypeName        = 'Windows.DeviceLink.Research.RuntimeInventory'
    RuntimeClassName  = $native.RuntimeClassName
    TrustLevel        = $native.TrustLevel
    InterfaceCount    = @($native.InterfaceIds).Count
    InterfaceIds      = @($native.InterfaceIds | ForEach-Object { $_.ToString('D').ToUpperInvariant() })
    KnownUtilitiesIid = '6410BEE7-60A9-5627-9EB2-FEDA7518A4EB'
    MetadataFiles     = $resolvedMetadata
    MetadataError     = $metadataError
    ReadOnly          = $true
}
