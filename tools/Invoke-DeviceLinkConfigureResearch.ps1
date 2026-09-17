<#
.SYNOPSIS
Runs one guarded DeviceLink Configure operation for controlled research.

.DESCRIPTION
Performs DeviceLink discovery first, validates that the device is preassociated, and then invokes
ConfigureDeviceLinkAsync exactly once using the discovered URL and tenant ID. The third headers
argument is passed as null, matching the observed public implementation used for Device Association.

THIS OPERATION IS STATE-CHANGING. A successful ConfigureDeviceLinkAsync call can retrieve and apply
the tenant-signed DeviceLink association, write DeviceLink JWT state to UEFI, acknowledge the
association to the service, and move tenant-side association state toward associated.

Safety boundaries:
- requires explicit -ConfirmStateChange
- refuses to continue unless ConfigureDeviceLinkResult is 0 before the operation
- requires discovery result 1 or 2 and non-empty discovery URL / tenant ID
- invokes ConfigureDeviceLinkAsync only once
- no retry
- no cleanup
- no firmware reset
- no cloud deletion
- no reboot
- returns exact async status / HRESULT and post-call configure result

The DeviceLink identity is never printed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceLinkBase64,

    [Parameter(Mandatory)]
    [switch]$ConfirmStateChange,

    [ValidateRange(5,600)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference='Stop'

if(-not $ConfirmStateChange){
    throw 'Refusing to invoke ConfigureDeviceLinkAsync without -ConfirmStateChange.'
}

$typeName='WindowsDeviceLinkResearch.DeviceLinkConfigureV1'
if(-not ($typeName -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WindowsDeviceLinkResearch
{
    public sealed class DeviceLinkConfigureResult
    {
        public int ConfigureResultBefore { get; set; }
        public int ConfigureResultAfter { get; set; }
        public int DiscoveryResult { get; set; }
        public string DiscoveryUrl { get; set; }
        public string TenantId { get; set; }
        public int DiscoveryAsyncStatus { get; set; }
        public int ConfigureAsyncStatus { get; set; }
        public int ConfigureAsyncError { get; set; }
        public int ConfigureOperationResult { get; set; }
        public bool ConfigureInvoked { get; set; }
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

    public static class DeviceLinkConfigureV1
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
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetResultsIntDelegate(IntPtr self, out int result);

        public static DeviceLinkConfigureResult Configure(string deviceLinkBase64, int timeoutSeconds)
        {
            IntPtr className=IntPtr.Zero, instance=IntPtr.Zero, blob=IntPtr.Zero;
            IntPtr discoveryOp=IntPtr.Zero, infoPtr=IntPtr.Zero;
            IntPtr hUrl=IntPtr.Zero, hTenant=IntPtr.Zero, configureOp=IntPtr.Zero;
            bool uninit=false;
            try
            {
                int init=RoInitialize(1);
                uninit=init>=0;
                ThrowIfFailed(WindowsCreateString(RuntimeClassName,RuntimeClassName.Length,out className),"WindowsCreateString(class)");
                ThrowIfFailed(RoActivateInstance(className,out instance),"RoActivateInstance(DeviceLinkManager)");
                var mgr=(IDeviceLinkManager)Marshal.GetObjectForIUnknown(instance);

                int before;
                ThrowIfFailed(mgr.GetConfigureDeviceLinkResult(out before),"GetConfigureDeviceLinkResult(before)");
                if(before!=0) throw new InvalidOperationException("Refusing ConfigureDeviceLinkAsync because current configure result is "+before+", expected 0.");

                ThrowIfFailed(WindowsCreateString(deviceLinkBase64,deviceLinkBase64.Length,out blob),"WindowsCreateString(DeviceLink)");
                ThrowIfFailed(mgr.RequestDiscoveryUrlAsync(blob,out discoveryOp),"RequestDiscoveryUrlAsync");
                WindowsDeleteString(blob); blob=IntPtr.Zero;

                int discoveryStatus=WaitForTerminal((IAsyncInfo)Marshal.GetObjectForIUnknown(discoveryOp),timeoutSeconds,"RequestDiscoveryUrlAsync",false);

                IntPtr discoveryVtable=Marshal.ReadIntPtr(discoveryOp);
                IntPtr discoveryFn=Marshal.ReadIntPtr(discoveryVtable,8*IntPtr.Size);
                var getDiscoveryResults=(GetResultsObjectDelegate)Marshal.GetDelegateForFunctionPointer(discoveryFn,typeof(GetResultsObjectDelegate));
                ThrowIfFailed(getDiscoveryResults(discoveryOp,out infoPtr),"RequestDiscoveryUrlAsync.GetResults");
                if(infoPtr==IntPtr.Zero) throw new InvalidOperationException("RequestDiscoveryUrlAsync returned a null result object.");

                var info=(IDiscoveryUrlRequestInfo)Marshal.GetObjectForIUnknown(infoPtr);
                int discoveryResult;
                ThrowIfFailed(info.get_DiscoveryUrl(out hUrl),"DiscoveryUrlRequestInfo.DiscoveryUrl");
                ThrowIfFailed(info.get_TenantId(out hTenant),"DiscoveryUrlRequestInfo.TenantId");
                ThrowIfFailed(info.get_DiscoveryUrlRequestResultValue(out discoveryResult),"DiscoveryUrlRequestInfo.ResultValue");

                string url=HStringToString(hUrl);
                string tenant=HStringToString(hTenant);
                if(discoveryResult!=1 && discoveryResult!=2)
                    throw new InvalidOperationException("Refusing ConfigureDeviceLinkAsync because discovery result is "+discoveryResult+"; expected 1 or 2.");
                if(String.IsNullOrWhiteSpace(url) || String.IsNullOrWhiteSpace(tenant))
                    throw new InvalidOperationException("Refusing ConfigureDeviceLinkAsync because discovery URL or tenant ID is empty.");

                // Single state-changing call. No retries.
                ThrowIfFailed(mgr.ConfigureDeviceLinkAsync(hUrl,hTenant,IntPtr.Zero,out configureOp),"ConfigureDeviceLinkAsync");
                if(configureOp==IntPtr.Zero) throw new InvalidOperationException("ConfigureDeviceLinkAsync returned a null async operation.");

                var configureInfo=(IAsyncInfo)Marshal.GetObjectForIUnknown(configureOp);
                int configureStatus;
                int configureError=WaitForTerminal(configureInfo,timeoutSeconds,"ConfigureDeviceLinkAsync",true,out configureStatus);

                int operationResult=-1;
                if(configureStatus==1 && configureError==0)
                {
                    IntPtr configureVtable=Marshal.ReadIntPtr(configureOp);
                    IntPtr configureFn=Marshal.ReadIntPtr(configureVtable,10*IntPtr.Size);
                    var getConfigureResults=(GetResultsIntDelegate)Marshal.GetDelegateForFunctionPointer(configureFn,typeof(GetResultsIntDelegate));
                    int hr=getConfigureResults(configureOp,out operationResult);
                    if(hr<0) operationResult=-1;
                }

                int after;
                ThrowIfFailed(mgr.GetConfigureDeviceLinkResult(out after),"GetConfigureDeviceLinkResult(after)");

                return new DeviceLinkConfigureResult
                {
                    ConfigureResultBefore=before,
                    ConfigureResultAfter=after,
                    DiscoveryResult=discoveryResult,
                    DiscoveryUrl=url,
                    TenantId=tenant,
                    DiscoveryAsyncStatus=discoveryStatus,
                    ConfigureAsyncStatus=configureStatus,
                    ConfigureAsyncError=configureError,
                    ConfigureOperationResult=operationResult,
                    ConfigureInvoked=true
                };
            }
            finally
            {
                if(configureOp!=IntPtr.Zero) Marshal.Release(configureOp);
                if(hUrl!=IntPtr.Zero) WindowsDeleteString(hUrl);
                if(hTenant!=IntPtr.Zero) WindowsDeleteString(hTenant);
                if(infoPtr!=IntPtr.Zero) Marshal.Release(infoPtr);
                if(discoveryOp!=IntPtr.Zero) Marshal.Release(discoveryOp);
                if(blob!=IntPtr.Zero) WindowsDeleteString(blob);
                if(instance!=IntPtr.Zero) Marshal.Release(instance);
                if(className!=IntPtr.Zero) WindowsDeleteString(className);
                if(uninit) RoUninitialize();
            }
        }

        private static int WaitForTerminal(IAsyncInfo ai,int timeoutSeconds,string operation,bool returnErrorOnly)
        {
            int status;
            int ignored;
            int error=WaitForTerminal(ai,timeoutSeconds,operation,returnErrorOnly,out status);
            if(returnErrorOnly) return error;
            return status;
        }

        private static int WaitForTerminal(IAsyncInfo ai,int timeoutSeconds,string operation,bool returnErrorOnly,out int status)
        {
            var deadline=DateTime.UtcNow.AddSeconds(timeoutSeconds);
            do
            {
                System.Threading.Thread.Sleep(250);
                ThrowIfFailed(ai.get_Status(out status),operation+".Status");
                if(DateTime.UtcNow>deadline) throw new TimeoutException(operation+" timed out with status "+status+".");
            } while(status==0);

            if(status==3)
            {
                int error;
                ai.get_ErrorCode(out error);
                if(returnErrorOnly) return error;
                throw new COMException(operation+" failed with HRESULT 0x"+error.ToString("X8")+".",error);
            }
            if(status==2)
            {
                if(returnErrorOnly) return unchecked((int)0x80004004);
                throw new OperationCanceledException(operation+" was canceled.");
            }
            return 0;
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

$result=[WindowsDeviceLinkResearch.DeviceLinkConfigureV1]::Configure($DeviceLinkBase64,$TimeoutSeconds)

# Preserve signed HRESULT and also show canonical hex form without PowerShell's signed->UInt32 cast issue.
$configureErrorHex='0x{0:X8}' -f ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$result.ConfigureAsyncError),0))

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.Configure'
    ConfigureResultBefore=$result.ConfigureResultBefore
    ConfigureResultAfter=$result.ConfigureResultAfter
    DiscoveryResult=$result.DiscoveryResult
    DiscoveryUrl=$result.DiscoveryUrl
    TenantId=$result.TenantId
    DiscoveryAsyncStatus=$result.DiscoveryAsyncStatus
    ConfigureAsyncStatus=$result.ConfigureAsyncStatus
    ConfigureAsyncError=$configureErrorHex
    ConfigureOperationResult=$result.ConfigureOperationResult
    ConfigureInvoked=$result.ConfigureInvoked
    RetryCount=0
    CleanupInvoked=$false
    RebootInvoked=$false
    StateChanging=$true
}
