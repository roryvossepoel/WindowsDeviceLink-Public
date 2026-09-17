using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace WinPEDeviceLink.Native
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
    }

    public static class DeviceLinkManagerClient
    {
        private const string RuntimeClassName = "ModernDeployment.Autopilot.Core.DeviceLinkManager";
        private const int AsyncStatusStarted = 0;
        private const int AsyncStatusCompleted = 1;
        private const int AsyncStatusCanceled = 2;
        private const int AsyncStatusError = 3;

        [ComImport, Guid("1F79101B-A792-5008-A82A-A4B232229026"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDeviceLinkManager
        {
            [PreserveSig] int GetIids(out int count, out IntPtr values);
            [PreserveSig] int GetRuntimeClassName(out IntPtr name);
            [PreserveSig] int GetTrustLevel(out int level);
            [PreserveSig] int GetDiscoveryUrlRequestInfo(out IntPtr info);
            [PreserveSig] int RequestDiscoveryUrlAsync(IntPtr deviceLinkInfo, out IntPtr operation);
            [PreserveSig] int GetConfigureDeviceLinkResult(out int result);
            [PreserveSig] int ConfigureDeviceLinkAsync(IntPtr url, IntPtr tenant, IntPtr headers, out IntPtr operation);
        }

        [ComImport, Guid("B93C372F-472F-4BEA-B90B-9FAA9BDC178F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDiscoveryUrlRequestInfo
        {
            [PreserveSig] int GetIids(out int count, out IntPtr values);
            [PreserveSig] int GetRuntimeClassName(out IntPtr name);
            [PreserveSig] int GetTrustLevel(out int level);
            [PreserveSig] int get_DiscoveryUrl(out IntPtr value);
            [PreserveSig] int get_TenantId(out IntPtr value);
            [PreserveSig] int get_DiscoveryUrlRequestResultValue(out int value);
        }

        [ComImport, Guid("00000036-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAsyncInfo
        {
            [PreserveSig] int GetIids(out int count, out IntPtr values);
            [PreserveSig] int GetRuntimeClassName(out IntPtr name);
            [PreserveSig] int GetTrustLevel(out int level);
            [PreserveSig] int get_Id(out uint id);
            [PreserveSig] int get_Status(out int status);
            [PreserveSig] int get_ErrorCode(out int errorCode);
            [PreserveSig] int Cancel();
            [PreserveSig] int Close();
        }

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

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetResultsObjectDelegate(IntPtr self, out IntPtr result);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetResultsIntDelegate(IntPtr self, out int result);

        public static DeviceLinkDiscoveryResult DiscoverRegistered(string deviceLinkBase64, int timeoutSeconds)
        {
            if (String.IsNullOrWhiteSpace(deviceLinkBase64)) throw new ArgumentException("DeviceLink identity is required.", "deviceLinkBase64");
            if (timeoutSeconds < 5) throw new ArgumentOutOfRangeException("timeoutSeconds");

            IntPtr className = IntPtr.Zero;
            IntPtr instance = IntPtr.Zero;
            IntPtr blob = IntPtr.Zero;
            IntPtr operation = IntPtr.Zero;
            IntPtr resultObject = IntPtr.Zero;
            IntPtr discoveryUrl = IntPtr.Zero;
            IntPtr tenantId = IntPtr.Zero;
            bool uninitialize = false;

            try
            {
                int init = RoInitialize(1);
                uninitialize = init >= 0;
                ThrowIfFailed(WindowsCreateString(RuntimeClassName, RuntimeClassName.Length, out className), "WindowsCreateString(class)");
                ThrowIfFailed(RoActivateInstance(className, out instance), "RoActivateInstance(DeviceLinkManager)");
                IDeviceLinkManager manager = (IDeviceLinkManager)Marshal.GetObjectForIUnknown(instance);

                int before;
                ThrowIfFailed(manager.GetConfigureDeviceLinkResult(out before), "GetConfigureDeviceLinkResult(before)");

                ThrowIfFailed(WindowsCreateString(deviceLinkBase64, deviceLinkBase64.Length, out blob), "WindowsCreateString(DeviceLink)");
                ThrowIfFailed(manager.RequestDiscoveryUrlAsync(blob, out operation), "RequestDiscoveryUrlAsync");
                WindowsDeleteString(blob);
                blob = IntPtr.Zero;

                int status;
                WaitForTerminal((IAsyncInfo)Marshal.GetObjectForIUnknown(operation), timeoutSeconds, "RequestDiscoveryUrlAsync", false, out status);

                resultObject = GetObjectResult(operation, 8, "RequestDiscoveryUrlAsync.GetResults");
                if (resultObject == IntPtr.Zero) throw new InvalidOperationException("RequestDiscoveryUrlAsync returned a null result object.");

                IDiscoveryUrlRequestInfo info = (IDiscoveryUrlRequestInfo)Marshal.GetObjectForIUnknown(resultObject);
                int discoveryResult;
                ThrowIfFailed(info.get_DiscoveryUrl(out discoveryUrl), "DiscoveryUrlRequestInfo.DiscoveryUrl");
                ThrowIfFailed(info.get_TenantId(out tenantId), "DiscoveryUrlRequestInfo.TenantId");
                ThrowIfFailed(info.get_DiscoveryUrlRequestResultValue(out discoveryResult), "DiscoveryUrlRequestInfo.ResultValue");

                int after;
                ThrowIfFailed(manager.GetConfigureDeviceLinkResult(out after), "GetConfigureDeviceLinkResult(after)");

                return new DeviceLinkDiscoveryResult
                {
                    ConfigureResultBefore = before,
                    ConfigureResultAfter = after,
                    DiscoveryResult = discoveryResult,
                    DiscoveryUrl = HStringToString(discoveryUrl),
                    TenantId = HStringToString(tenantId),
                    AsyncStatus = status
                };
            }
            finally
            {
                if (discoveryUrl != IntPtr.Zero) WindowsDeleteString(discoveryUrl);
                if (tenantId != IntPtr.Zero) WindowsDeleteString(tenantId);
                Release(resultObject);
                Release(operation);
                if (blob != IntPtr.Zero) WindowsDeleteString(blob);
                Release(instance);
                if (className != IntPtr.Zero) WindowsDeleteString(className);
                if (uninitialize) RoUninitialize();
            }
        }

        public static DeviceLinkConfigureResult ConfigureRegistered(string deviceLinkBase64, int timeoutSeconds)
        {
            if (String.IsNullOrWhiteSpace(deviceLinkBase64)) throw new ArgumentException("DeviceLink identity is required.", "deviceLinkBase64");
            if (timeoutSeconds < 5) throw new ArgumentOutOfRangeException("timeoutSeconds");

            IntPtr className = IntPtr.Zero;
            IntPtr instance = IntPtr.Zero;
            IntPtr blob = IntPtr.Zero;
            IntPtr discoveryOperation = IntPtr.Zero;
            IntPtr resultObject = IntPtr.Zero;
            IntPtr discoveryUrl = IntPtr.Zero;
            IntPtr tenantId = IntPtr.Zero;
            IntPtr configureOperation = IntPtr.Zero;
            bool uninitialize = false;

            try
            {
                int init = RoInitialize(1);
                uninitialize = init >= 0;
                ThrowIfFailed(WindowsCreateString(RuntimeClassName, RuntimeClassName.Length, out className), "WindowsCreateString(class)");
                ThrowIfFailed(RoActivateInstance(className, out instance), "RoActivateInstance(DeviceLinkManager)");
                IDeviceLinkManager manager = (IDeviceLinkManager)Marshal.GetObjectForIUnknown(instance);

                int before;
                ThrowIfFailed(manager.GetConfigureDeviceLinkResult(out before), "GetConfigureDeviceLinkResult(before)");
                if (before != 0)
                {
                    throw new InvalidOperationException("ConfigureDeviceLinkAsync was refused because the current configure result is " + before + ", expected 0.");
                }

                ThrowIfFailed(WindowsCreateString(deviceLinkBase64, deviceLinkBase64.Length, out blob), "WindowsCreateString(DeviceLink)");
                ThrowIfFailed(manager.RequestDiscoveryUrlAsync(blob, out discoveryOperation), "RequestDiscoveryUrlAsync");
                WindowsDeleteString(blob);
                blob = IntPtr.Zero;

                int discoveryStatus;
                WaitForTerminal((IAsyncInfo)Marshal.GetObjectForIUnknown(discoveryOperation), timeoutSeconds, "RequestDiscoveryUrlAsync", false, out discoveryStatus);

                resultObject = GetObjectResult(discoveryOperation, 8, "RequestDiscoveryUrlAsync.GetResults");
                if (resultObject == IntPtr.Zero) throw new InvalidOperationException("RequestDiscoveryUrlAsync returned a null result object.");

                IDiscoveryUrlRequestInfo info = (IDiscoveryUrlRequestInfo)Marshal.GetObjectForIUnknown(resultObject);
                int discoveryResult;
                ThrowIfFailed(info.get_DiscoveryUrl(out discoveryUrl), "DiscoveryUrlRequestInfo.DiscoveryUrl");
                ThrowIfFailed(info.get_TenantId(out tenantId), "DiscoveryUrlRequestInfo.TenantId");
                ThrowIfFailed(info.get_DiscoveryUrlRequestResultValue(out discoveryResult), "DiscoveryUrlRequestInfo.ResultValue");

                string url = HStringToString(discoveryUrl);
                string tenant = HStringToString(tenantId);
                if (discoveryResult != 1 && discoveryResult != 2)
                {
                    throw new InvalidOperationException("ConfigureDeviceLinkAsync was refused because discovery result is " + discoveryResult + ", expected 1 or 2.");
                }
                if (String.IsNullOrWhiteSpace(url) || String.IsNullOrWhiteSpace(tenant))
                {
                    throw new InvalidOperationException("ConfigureDeviceLinkAsync was refused because discovery URL or tenant ID is empty.");
                }

                ThrowIfFailed(manager.ConfigureDeviceLinkAsync(discoveryUrl, tenantId, IntPtr.Zero, out configureOperation), "ConfigureDeviceLinkAsync");
                if (configureOperation == IntPtr.Zero) throw new InvalidOperationException("ConfigureDeviceLinkAsync returned a null async operation.");

                int configureStatus;
                int configureError = WaitForTerminal((IAsyncInfo)Marshal.GetObjectForIUnknown(configureOperation), timeoutSeconds, "ConfigureDeviceLinkAsync", true, out configureStatus);

                int operationResult = -1;
                if (configureStatus == AsyncStatusCompleted && configureError == 0)
                {
                    operationResult = GetIntResult(configureOperation, 10);
                }

                int after;
                ThrowIfFailed(manager.GetConfigureDeviceLinkResult(out after), "GetConfigureDeviceLinkResult(after)");

                return new DeviceLinkConfigureResult
                {
                    ConfigureResultBefore = before,
                    ConfigureResultAfter = after,
                    DiscoveryResult = discoveryResult,
                    DiscoveryUrl = url,
                    TenantId = tenant,
                    DiscoveryAsyncStatus = discoveryStatus,
                    ConfigureAsyncStatus = configureStatus,
                    ConfigureAsyncError = configureError,
                    ConfigureOperationResult = operationResult
                };
            }
            finally
            {
                Release(configureOperation);
                if (discoveryUrl != IntPtr.Zero) WindowsDeleteString(discoveryUrl);
                if (tenantId != IntPtr.Zero) WindowsDeleteString(tenantId);
                Release(resultObject);
                Release(discoveryOperation);
                if (blob != IntPtr.Zero) WindowsDeleteString(blob);
                Release(instance);
                if (className != IntPtr.Zero) WindowsDeleteString(className);
                if (uninitialize) RoUninitialize();
            }
        }

        private static int WaitForTerminal(IAsyncInfo asyncInfo, int timeoutSeconds, string operation, bool returnErrorOnly, out int status)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
            do
            {
                Thread.Sleep(250);
                ThrowIfFailed(asyncInfo.get_Status(out status), operation + ".Status");
                if (DateTime.UtcNow > deadline) throw new TimeoutException(operation + " timed out with status " + status + ".");
            }
            while (status == AsyncStatusStarted);

            if (status == AsyncStatusError)
            {
                int errorCode;
                ThrowIfFailed(asyncInfo.get_ErrorCode(out errorCode), operation + ".ErrorCode");
                if (returnErrorOnly) return errorCode;
                throw new COMException(operation + " failed with HRESULT 0x" + errorCode.ToString("X8") + ".", errorCode);
            }

            if (status == AsyncStatusCanceled)
            {
                if (returnErrorOnly) return unchecked((int)0x80004004);
                throw new OperationCanceledException(operation + " was canceled.");
            }

            if (status != AsyncStatusCompleted)
            {
                throw new InvalidOperationException(operation + " returned async status " + status + ".");
            }

            return 0;
        }

        private static IntPtr GetObjectResult(IntPtr operation, int slot, string operationName)
        {
            IntPtr vtable = Marshal.ReadIntPtr(operation);
            IntPtr method = Marshal.ReadIntPtr(vtable, slot * IntPtr.Size);
            GetResultsObjectDelegate getResults = (GetResultsObjectDelegate)Marshal.GetDelegateForFunctionPointer(method, typeof(GetResultsObjectDelegate));
            IntPtr result;
            ThrowIfFailed(getResults(operation, out result), operationName);
            return result;
        }

        private static int GetIntResult(IntPtr operation, int slot)
        {
            IntPtr vtable = Marshal.ReadIntPtr(operation);
            IntPtr method = Marshal.ReadIntPtr(vtable, slot * IntPtr.Size);
            GetResultsIntDelegate getResults = (GetResultsIntDelegate)Marshal.GetDelegateForFunctionPointer(method, typeof(GetResultsIntDelegate));
            int result;
            int hr = getResults(operation, out result);
            return hr < 0 ? -1 : result;
        }

        private static string HStringToString(IntPtr hstring)
        {
            if (hstring == IntPtr.Zero) return null;
            uint length;
            IntPtr buffer = WindowsGetStringRawBuffer(hstring, out length);
            return buffer == IntPtr.Zero ? null : Marshal.PtrToStringUni(buffer, checked((int)length));
        }

        private static void ThrowIfFailed(int hr, string operation)
        {
            if (hr < 0) throw new COMException(operation + " failed with HRESULT 0x" + hr.ToString("X8") + ".", hr);
        }

        private static void Release(IntPtr value)
        {
            if (value != IntPtr.Zero) Marshal.Release(value);
        }
    }
}
