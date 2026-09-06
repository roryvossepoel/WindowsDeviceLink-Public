using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace WinPEDeviceLink.Native
{
    public sealed class ProbeResult { public bool Success { get; set; } public string Message { get; set; } }

    public static class DeviceLinkClient
    {
        private const int DeviceLinkFormatJsonBase64 = 33;
        private const int AsyncStatusCompleted = 1;
        private const int AsyncStatusCanceled = 2;
        private const int AsyncStatusError = 3;
        private static readonly Guid IAsyncInfoId = new Guid("00000036-0000-0000-C000-000000000046");
        private static readonly Guid IDeviceLinkUtilitiesId = new Guid("6410BEE7-60A9-5627-9EB2-FEDA7518A4EB");
        private const string RuntimeClassName = "ModernDeployment.Autopilot.Core.DeviceLinkUtilities";

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr LoadLibraryEx(string fileName, IntPtr file, uint flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)] private static extern IntPtr GetProcAddress(IntPtr module, string name);
        [DllImport("combase.dll")] private static extern int RoInitialize(uint initType);
        [DllImport("combase.dll")] private static extern void RoUninitialize();
        [DllImport("combase.dll")] private static extern int RoActivateInstance(IntPtr activatableClassId, out IntPtr instance);
        [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string sourceString, int length, out IntPtr hstring);
        [DllImport("combase.dll")] private static extern int WindowsDeleteString(IntPtr hstring);
        [DllImport("combase.dll")] private static extern IntPtr WindowsGetStringRawBuffer(IntPtr hstring, out uint length);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int DllGetActivationFactoryDelegate(IntPtr activatableClassId, out IntPtr activationFactory);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int QueryInterfaceDelegate(IntPtr self, ref Guid iid, out IntPtr result);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int ActivateInstanceDelegate(IntPtr self, out IntPtr instance);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int ExportDeviceLinkInfoCsvAsyncDelegate(IntPtr self, IntPtr folder, int format, out IntPtr operation);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int GetDeviceLinkInfoAsyncDelegate(IntPtr self, int format, out IntPtr operation);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int GetAsyncStatusDelegate(IntPtr self, out int status);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int GetAsyncErrorCodeDelegate(IntPtr self, out int errorCode);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int GetStringResultsDelegate(IntPtr self, out IntPtr result);

        public static ProbeResult TestRegistered() { return ProbeRegistered(); }
        private static ProbeResult ProbeRegistered()
        {
            IntPtr instance=IntPtr.Zero, utilities=IntPtr.Zero, className=IntPtr.Zero; bool uninit=false;
            try { int r=RoInitialize(0); uninit=r>=0; ThrowIfFailed(WindowsCreateString(RuntimeClassName,RuntimeClassName.Length,out className),"WindowsCreateString"); ThrowIfFailed(RoActivateInstance(className,out instance),"RoActivateInstance"); ThrowIfFailed(QueryInterface(instance,IDeviceLinkUtilitiesId,out utilities),"QueryInterface(IDeviceLinkUtilities)"); return new ProbeResult{Success=true,Message="Registered DeviceLink runtime activation succeeded."}; }
            catch(Exception e){ return new ProbeResult{Success=false,Message=e.Message}; }
            finally { Release(utilities); Release(instance); if(className!=IntPtr.Zero)WindowsDeleteString(className); if(uninit)RoUninitialize(); }
        }

        public static ProbeResult Test(string dllPath)
        {
            IntPtr factory=IntPtr.Zero,instance=IntPtr.Zero,utilities=IntPtr.Zero,className=IntPtr.Zero; bool uninit=false;
            try { int r=RoInitialize(0); uninit=r>=0; ActivateDirect(dllPath,out factory,out instance,out utilities,out className); return new ProbeResult{Success=true,Message="DeviceLink activation succeeded."}; }
            catch(Exception e){ return new ProbeResult{Success=false,Message=e.Message}; }
            finally { Release(utilities);Release(instance);Release(factory);if(className!=IntPtr.Zero)WindowsDeleteString(className);if(uninit)RoUninitialize(); }
        }

        public static string GetDeviceLinkRegistered(int timeoutSeconds)
        {
            IntPtr instance=IntPtr.Zero,utilities=IntPtr.Zero,className=IntPtr.Zero; bool uninit=false;
            try { int r=RoInitialize(0);uninit=r>=0;ThrowIfFailed(WindowsCreateString(RuntimeClassName,RuntimeClassName.Length,out className),"WindowsCreateString");ThrowIfFailed(RoActivateInstance(className,out instance),"RoActivateInstance");ThrowIfFailed(QueryInterface(instance,IDeviceLinkUtilitiesId,out utilities),"QueryInterface(IDeviceLinkUtilities)");return GetDeviceLinkFromUtilities(utilities,timeoutSeconds); }
            finally { Release(utilities);Release(instance);if(className!=IntPtr.Zero)WindowsDeleteString(className);if(uninit)RoUninitialize(); }
        }

        public static string GetDeviceLink(string dllPath,int timeoutSeconds)
        {
            IntPtr factory=IntPtr.Zero,instance=IntPtr.Zero,utilities=IntPtr.Zero,className=IntPtr.Zero;bool uninit=false;
            try { int r=RoInitialize(0);uninit=r>=0;ActivateDirect(dllPath,out factory,out instance,out utilities,out className);return GetDeviceLinkFromUtilities(utilities,timeoutSeconds); }
            finally { Release(utilities);Release(instance);Release(factory);if(className!=IntPtr.Zero)WindowsDeleteString(className);if(uninit)RoUninitialize(); }
        }

        public static string ExportCsvRegistered(string folder,int timeoutSeconds)
        {
            IntPtr instance=IntPtr.Zero,utilities=IntPtr.Zero,className=IntPtr.Zero;bool uninit=false;
            try { int r=RoInitialize(1);uninit=r>=0;ThrowIfFailed(WindowsCreateString(RuntimeClassName,RuntimeClassName.Length,out className),"WindowsCreateString");ThrowIfFailed(RoActivateInstance(className,out instance),"RoActivateInstance");ThrowIfFailed(QueryInterface(instance,IDeviceLinkUtilitiesId,out utilities),"QueryInterface(IDeviceLinkUtilities)");return ExportCsvFromUtilities(utilities,folder,timeoutSeconds); }
            finally { Release(utilities);Release(instance);if(className!=IntPtr.Zero)WindowsDeleteString(className);if(uninit)RoUninitialize(); }
        }

        public static string ExportCsv(string dllPath,string folder,int timeoutSeconds)
        {
            IntPtr factory=IntPtr.Zero,instance=IntPtr.Zero,utilities=IntPtr.Zero,className=IntPtr.Zero;bool uninit=false;
            try { int r=RoInitialize(1);uninit=r>=0;ActivateDirect(dllPath,out factory,out instance,out utilities,out className);return ExportCsvFromUtilities(utilities,folder,timeoutSeconds); }
            finally { Release(utilities);Release(instance);Release(factory);if(className!=IntPtr.Zero)WindowsDeleteString(className);if(uninit)RoUninitialize(); }
        }

        private static string ExportCsvFromUtilities(IntPtr utilities,string folder,int timeoutSeconds)
        {
            if(!Directory.Exists(folder))Directory.CreateDirectory(folder);
            IntPtr folderString=IntPtr.Zero,operation=IntPtr.Zero,asyncInfo=IntPtr.Zero;
            try {
                ThrowIfFailed(WindowsCreateString(folder,folder.Length,out folderString),"WindowsCreateString(folder)");
                var export=GetVtableDelegate<ExportDeviceLinkInfoCsvAsyncDelegate>(utilities,6);
                int hr=export(utilities,folderString,DeviceLinkFormatJsonBase64,out operation);
                ThrowIfFailed(hr,"ExportDeviceLinkInfoCsvAsync(format=33, folder="+folder+")");
                ThrowIfFailed(QueryInterface(operation,IAsyncInfoId,out asyncInfo),"QueryInterface(IAsyncInfo)");
                WaitForCompletion(asyncInfo,timeoutSeconds,"ExportDeviceLinkInfoCsvAsync");
                string newest=null;DateTime newestTime=DateTime.MinValue;
                foreach(string file in Directory.GetFiles(folder,"*.devicelink.csv")) { DateTime t=File.GetLastWriteTimeUtc(file);if(t>=newestTime){newestTime=t;newest=file;} }
                if(newest==null)throw new InvalidOperationException("ExportDeviceLinkInfoCsvAsync completed but no *.devicelink.csv was created in '"+folder+"'.");
                return newest;
            }
            finally { Release(asyncInfo);Release(operation);if(folderString!=IntPtr.Zero)WindowsDeleteString(folderString); }
        }

        private static string GetDeviceLinkFromUtilities(IntPtr utilities,int timeoutSeconds)
        {
            IntPtr operation=IntPtr.Zero,asyncInfo=IntPtr.Zero,result=IntPtr.Zero;
            try { var get=GetVtableDelegate<GetDeviceLinkInfoAsyncDelegate>(utilities,7);ThrowIfFailed(get(utilities,DeviceLinkFormatJsonBase64,out operation),"GetDeviceLinkInfoAsync");ThrowIfFailed(QueryInterface(operation,IAsyncInfoId,out asyncInfo),"QueryInterface(IAsyncInfo)");WaitForCompletion(asyncInfo,timeoutSeconds,"DeviceLink generation");var results=GetVtableDelegate<GetStringResultsDelegate>(operation,8);ThrowIfFailed(results(operation,out result),"GetResults");uint len;IntPtr buffer=WindowsGetStringRawBuffer(result,out len);if(buffer==IntPtr.Zero||len==0)throw new InvalidOperationException("DeviceLink generation returned no data.");return Marshal.PtrToStringUni(buffer,checked((int)len)); }
            finally { if(result!=IntPtr.Zero)WindowsDeleteString(result);Release(asyncInfo);Release(operation); }
        }

        private static void WaitForCompletion(IntPtr asyncInfo,int timeoutSeconds,string name)
        {
            var statusFn=GetVtableDelegate<GetAsyncStatusDelegate>(asyncInfo,7);var sw=Stopwatch.StartNew();int status;
            while(true){ThrowIfFailed(statusFn(asyncInfo,out status),"IAsyncInfo.Status");if(status!=0)break;if(sw.Elapsed.TotalSeconds>=timeoutSeconds)throw new TimeoutException(name+" timed out.");Thread.Sleep(250);}
            if(status==AsyncStatusError){int ec;var err=GetVtableDelegate<GetAsyncErrorCodeDelegate>(asyncInfo,8);ThrowIfFailed(err(asyncInfo,out ec),"IAsyncInfo.ErrorCode");throw new COMException(name+" failed with HRESULT 0x"+ec.ToString("X8")+".",ec);}if(status==AsyncStatusCanceled)throw new OperationCanceledException(name+" was canceled.");if(status!=AsyncStatusCompleted)throw new InvalidOperationException(name+" returned async status "+status+".");
        }

        private static void ActivateDirect(string dllPath,out IntPtr factory,out IntPtr instance,out IntPtr utilities,out IntPtr className)
        {
            factory=instance=utilities=className=IntPtr.Zero;IntPtr module=LoadLibraryEx(dllPath,IntPtr.Zero,0x00001100);if(module==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"LoadLibraryEx failed");IntPtr ep=GetProcAddress(module,"DllGetActivationFactory");if(ep==IntPtr.Zero)throw new EntryPointNotFoundException("DllGetActivationFactory");ThrowIfFailed(WindowsCreateString(RuntimeClassName,RuntimeClassName.Length,out className),"WindowsCreateString");var gf=Marshal.GetDelegateForFunctionPointer<DllGetActivationFactoryDelegate>(ep);ThrowIfFailed(gf(className,out factory),"DllGetActivationFactory");var activate=GetVtableDelegate<ActivateInstanceDelegate>(factory,6);ThrowIfFailed(activate(factory,out instance),"ActivateInstance");ThrowIfFailed(QueryInterface(instance,IDeviceLinkUtilitiesId,out utilities),"QueryInterface(IDeviceLinkUtilities)");
        }
        private static int QueryInterface(IntPtr value,Guid iid,out IntPtr result){var q=GetVtableDelegate<QueryInterfaceDelegate>(value,0);return q(value,ref iid,out result);}
        private static T GetVtableDelegate<T>(IntPtr instance,int slot) where T:class{IntPtr table=Marshal.ReadIntPtr(instance);IntPtr method=Marshal.ReadIntPtr(table,slot*IntPtr.Size);return Marshal.GetDelegateForFunctionPointer(method,typeof(T)) as T;}
        private static void ThrowIfFailed(int hr,string operation){if(hr<0)throw new COMException(operation+" failed with HRESULT 0x"+hr.ToString("X8")+".",hr);}
        private static void Release(IntPtr value){if(value!=IntPtr.Zero)Marshal.Release(value);}
    }
}
