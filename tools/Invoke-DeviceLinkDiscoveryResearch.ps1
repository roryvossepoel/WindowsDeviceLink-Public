<#
.SYNOPSIS
Runs only the DeviceLink preassociation discovery operation for research.

.DESCRIPTION
Activates ModernDeployment.Autopilot.Core.DeviceLinkManager and uses the live ABI contract
validated against public tooling:
  slot 6 GetDiscoveryUrlRequestInfo
  slot 7 RequestDiscoveryUrlAsync
  slot 8 GetConfigureDeviceLinkResult
  slot 9 ConfigureDeviceLinkAsync

This probe invokes ONLY RequestDiscoveryUrlAsync (slot 7) and read-only status/property getters.
It does NOT invoke ConfigureDeviceLinkAsync, does NOT write the association JWT to firmware,
does NOT acknowledge an association, does NOT modify Intune/Graph state, and does NOT reboot.

The supplied DeviceLink identity remains in-process and is never printed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceLinkBase64,

    [ValidateRange(5,600)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference='Stop'

$typeName='WindowsDeviceLinkResearch.DeviceLinkDiscoveryV1'
if(-not ($typeName -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WindowsDeviceLinkResearch
{
    public sealed class DeviceLinkDiscoveryResult
    {
        public int ConfigureResultBefore { get; set; }
        public int ConfigureResultAfter { get; set; }
        public int DiscoveryResult { get; set; }
        public string DiscoveryUrl { get; set; }
        public string TenantId { get; set; }
        public int AsyncStatus { get; set; }
    }

    [ComImport, Guid("1F79101B-A792-5008-A82A-A4B232229026"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDeviceLinkManager
    {
        [PreserveSig] int GetIids(out int c, out IntPtr p);
        [PreserveSig] int GetRuntimeClassName(out IntPtr n);
        [PreserveSig] int GetTrustLevel(out int l);
        [PreserveSig] int GetDiscoveryUrlRequestInfo(out IntPtr info);
        [PreserveSig] int RequestDiscoveryUrlAsync(IntPtr deviceLinkInfo, out IntPtr op);
        [PreserveSig] int GetConfigureDeviceLinkResult(out int result);
        [PreserveSig] int ConfigureDeviceLinkAsync(IntPtr url, IntPtr tenant, IntPtr headers, out IntPtr op);
    }

    [ComImport, Guid("B93C372F-472F-4BEA-B90B-9FAA9BDC178F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDiscoveryUrlRequestInfo
    {
        [PreserveSig] int GetIids(out int c, out IntPtr p);
        [PreserveSig] int GetRuntimeClassName(out IntPtr n);
        [PreserveSig] int GetTrustLevel(out int l);
        [PreserveSig] int get_DiscoveryUrl(out IntPtr h);
        [PreserveSig] int get_TenantId(out IntPtr h);
        [PreserveSig] int get_DiscoveryUrlRequestResultValue(out int v);
    }

    [ComImport, Guid("00000036-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAsyncInfo
    {
        [PreserveSig] int GetIids(out int c, out IntPtr p);
        [PreserveSig] int GetRuntimeClassName(out IntPtr n);
        [PreserveSig] int GetTrustLevel(out int l);
        [PreserveSig] int get_Id(out uint id);
        [PreserveSig] int get_Status(out int status);
        [PreserveSig] int get_ErrorCode(out int errorCode);
        [PreserveSig] int Cancel();
        [PreserveSig] int Close();
    }

    public static class DeviceLinkDiscoveryV1
    {
        private const string RuntimeClassName = "ModernDeployment.Autopilot.Core.DeviceLinkManager";

        [DllImport("combase.dll")]
        private static extern int RoInitialize(uint initType);
        [DllImport("combase.dll")]
        private static extern void RoUninitialize();
        [DllImport("combase.dll")]
        private static extern int RoActivateInstance(IntPtr activatableClassId, out IntPtr instance);
        [DllImport("combase.dll", CharSet=CharSet.Unicode)]
        private static extern int WindowsCreateString(string sourceString, int length, out IntPtr hstring);
        [DllImport("combase.dll")]
        private static extern int WindowsDeleteString(IntPtr hstring);
        [DllImport("combase.dll")]
        private static extern IntPtr WindowsGetStringRawBuffer(IntPtr hstring, out uint length);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetResultsObjectDelegate(IntPtr self, out IntPtr result);

        public static DeviceLinkDiscoveryResult Discover(string deviceLinkBase64, int timeoutSeconds)
        {
            IntPtr className=IntPtr.Zero, instance=IntPtr.Zero, blob=IntPtr.Zero, op=IntPtr.Zero, infoPtr=IntPtr.Zero;
            bool uninit=false;
            try
            {
                int init=RoInitialize(1);
                uninit=init>=0;
                ThrowIfFailed(WindowsCreateString(RuntimeClassName, RuntimeClassName.Length, out className), "WindowsCreateString(class)");
                ThrowIfFailed(RoActivateInstance(className, out instance), "RoActivateInstance(DeviceLinkManager)");
                var mgr=(IDeviceLinkManager)Marshal.GetObjectForIUnknown(instance);

                int before;
                ThrowIfFailed(mgr.GetConfigureDeviceLinkResult(out before), "GetConfigureDeviceLinkResult(before)");

                ThrowIfFailed(WindowsCreateString(deviceLinkBase64, deviceLinkBase64.Length, out blob), "WindowsCreateString(DeviceLink)");
                ThrowIfFailed(mgr.RequestDiscoveryUrlAsync(blob, out op), "RequestDiscoveryUrlAsync");
                WindowsDeleteString(blob); blob=IntPtr.Zero;

                var asyncInfo=(IAsyncInfo)Marshal.GetObjectForIUnknown(op);
                int status;
                var deadline=DateTime.UtcNow.AddSeconds(timeoutSeconds);
                do
                {
                    System.Threading.Thread.Sleep(250);
                    ThrowIfFailed(asyncInfo.get_Status(out status), "RequestDiscoveryUrlAsync.Status");
                    if(DateTime.UtcNow>deadline) throw new TimeoutException("RequestDiscoveryUrlAsync timed out with status "+status+".");
                } while(status==0);

                if(status==3)
                {
                    int error;
                    asyncInfo.get_ErrorCode(out error);
                    throw new COMException("RequestDiscoveryUrlAsync failed with HRESULT 0x"+error.ToString("X8")+".",error);
                }
                if(status==2) throw new OperationCanceledException("RequestDiscoveryUrlAsync was canceled.");

                IntPtr vtable=Marshal.ReadIntPtr(op);
                IntPtr fn=Marshal.ReadIntPtr(vtable,8*IntPtr.Size);
                var getResults=(GetResultsObjectDelegate)Marshal.GetDelegateForFunctionPointer(fn,typeof(GetResultsObjectDelegate));
                ThrowIfFailed(getResults(op,out infoPtr),"RequestDiscoveryUrlAsync.GetResults");
                if(infoPtr==IntPtr.Zero) throw new InvalidOperationException("RequestDiscoveryUrlAsync returned a null result object.");

                var info=(IDiscoveryUrlRequestInfo)Marshal.GetObjectForIUnknown(infoPtr);
                IntPtr hUrl=IntPtr.Zero,hTenant=IntPtr.Zero;
                int discoveryResult;
                try
                {
                    ThrowIfFailed(info.get_DiscoveryUrl(out hUrl),"DiscoveryUrlRequestInfo.DiscoveryUrl");
                    ThrowIfFailed(info.get_TenantId(out hTenant),"DiscoveryUrlRequestInfo.TenantId");
                    ThrowIfFailed(info.get_DiscoveryUrlRequestResultValue(out discoveryResult),"DiscoveryUrlRequestInfo.ResultValue");

                    int after;
                    ThrowIfFailed(mgr.GetConfigureDeviceLinkResult(out after), "GetConfigureDeviceLinkResult(after)");

                    return new DeviceLinkDiscoveryResult
                    {
                        ConfigureResultBefore=before,
                        ConfigureResultAfter=after,
                        DiscoveryResult=discoveryResult,
                        DiscoveryUrl=HStringToString(hUrl),
                        TenantId=HStringToString(hTenant),
                        AsyncStatus=status
                    };
                }
                finally
                {
                    if(hUrl!=IntPtr.Zero) WindowsDeleteString(hUrl);
                    if(hTenant!=IntPtr.Zero) WindowsDeleteString(hTenant);
                }
            }
            finally
            {
                if(infoPtr!=IntPtr.Zero) Marshal.Release(infoPtr);
                if(op!=IntPtr.Zero) Marshal.Release(op);
                if(blob!=IntPtr.Zero) WindowsDeleteString(blob);
                if(instance!=IntPtr.Zero) Marshal.Release(instance);
                if(className!=IntPtr.Zero) WindowsDeleteString(className);
                if(uninit) RoUninitialize();
            }
        }

        private static string HStringToString(IntPtr h)
        {
            if(h==IntPtr.Zero) return null;
            uint len;
            IntPtr p=WindowsGetStringRawBuffer(h,out len);
            return p==IntPtr.Zero ? null : Marshal.PtrToStringUni(p,(int)len);
        }

        private static void ThrowIfFailed(int hr,string operation)
        {
            if(hr<0) throw new COMException(operation+" failed with HRESULT 0x"+hr.ToString("X8")+".",hr);
        }
    }
}
'@
}

$result=[WindowsDeviceLinkResearch.DeviceLinkDiscoveryV1]::Discover($DeviceLinkBase64,$TimeoutSeconds)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.Discovery'
    ConfigureResultBefore=$result.ConfigureResultBefore
    ConfigureResultAfter=$result.ConfigureResultAfter
    DiscoveryResult=$result.DiscoveryResult
    DiscoveryUrl=$result.DiscoveryUrl
    TenantId=$result.TenantId
    AsyncStatus=$result.AsyncStatus
    ConfigureInvoked=$false
    AssociationWriteInvoked=$false
    ReadOnlyLocalState=$true
}
