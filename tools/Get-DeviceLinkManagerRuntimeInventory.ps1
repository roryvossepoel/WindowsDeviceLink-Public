<#
.SYNOPSIS
Read-only WinRT inventory probe for ModernDeployment.Autopilot.Core.DeviceLinkManager.

.DESCRIPTION
Attempts to activate the DeviceLinkManager runtime class and, if successful, reads only
IInspectable metadata: runtime class name, trust level and interface IIDs. No DeviceLink
configuration/discovery/link/firmware/network operation is invoked.
#>
[CmdletBinding()]
param()

$ErrorActionPreference='Stop'

$typeName='WindowsDeviceLinkResearch.DeviceLinkManagerInventory'
if(-not ($typeName -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WindowsDeviceLinkResearch
{
    public sealed class DeviceLinkManagerInventoryResult
    {
        public bool Activated { get; set; }
        public int HResult { get; set; }
        public string Error { get; set; }
        public string RuntimeClassName { get; set; }
        public int TrustLevel { get; set; }
        public Guid[] InterfaceIds { get; set; }
    }

    public static class DeviceLinkManagerInventory
    {
        private const string TargetClass = "ModernDeployment.Autopilot.Core.DeviceLinkManager";

        [DllImport("combase.dll")] static extern int RoInitialize(uint initType);
        [DllImport("combase.dll")] static extern void RoUninitialize();
        [DllImport("combase.dll")] static extern int RoActivateInstance(IntPtr classId, out IntPtr instance);
        [DllImport("combase.dll", CharSet=CharSet.Unicode)] static extern int WindowsCreateString(string source, int length, out IntPtr hstring);
        [DllImport("combase.dll")] static extern int WindowsDeleteString(IntPtr hstring);
        [DllImport("combase.dll")] static extern IntPtr WindowsGetStringRawBuffer(IntPtr hstring, out uint length);
        [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr pv);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetIidsDelegate(IntPtr self, out uint count, out IntPtr iids);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetRuntimeClassNameDelegate(IntPtr self, out IntPtr className);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetTrustLevelDelegate(IntPtr self, out int trustLevel);

        public static DeviceLinkManagerInventoryResult Inspect()
        {
            IntPtr hs=IntPtr.Zero, instance=IntPtr.Zero, returnedName=IntPtr.Zero, iidBuffer=IntPtr.Zero;
            bool uninit=false;
            var result=new DeviceLinkManagerInventoryResult{ Activated=false, HResult=0, InterfaceIds=new Guid[0] };
            try
            {
                int init=RoInitialize(0); uninit=init>=0;
                int hr=WindowsCreateString(TargetClass, TargetClass.Length, out hs);
                if(hr<0){ result.HResult=hr; result.Error="WindowsCreateString"; return result; }
                hr=RoActivateInstance(hs, out instance);
                if(hr<0){ result.HResult=hr; result.Error="RoActivateInstance"; return result; }
                result.Activated=true;

                var getIids=GetVtableDelegate<GetIidsDelegate>(instance,3);
                uint count; hr=getIids(instance,out count,out iidBuffer);
                if(hr<0){ result.HResult=hr; result.Error="IInspectable.GetIids"; return result; }
                var ids=new List<Guid>(); int guidSize=Marshal.SizeOf(typeof(Guid));
                for(uint i=0;i<count;i++) ids.Add((Guid)Marshal.PtrToStructure(IntPtr.Add(iidBuffer, checked((int)(i*guidSize))), typeof(Guid)));
                result.InterfaceIds=ids.ToArray();

                var getName=GetVtableDelegate<GetRuntimeClassNameDelegate>(instance,4);
                hr=getName(instance,out returnedName);
                if(hr>=0){ uint len; IntPtr p=WindowsGetStringRawBuffer(returnedName,out len); result.RuntimeClassName=p==IntPtr.Zero?null:Marshal.PtrToStringUni(p,checked((int)len)); }

                var getTrust=GetVtableDelegate<GetTrustLevelDelegate>(instance,5);
                int trust; hr=getTrust(instance,out trust); if(hr>=0) result.TrustLevel=trust;
                result.HResult=0;
                return result;
            }
            finally
            {
                if(iidBuffer!=IntPtr.Zero) CoTaskMemFree(iidBuffer);
                if(returnedName!=IntPtr.Zero) WindowsDeleteString(returnedName);
                if(instance!=IntPtr.Zero) Marshal.Release(instance);
                if(hs!=IntPtr.Zero) WindowsDeleteString(hs);
                if(uninit) RoUninitialize();
            }
        }

        static T GetVtableDelegate<T>(IntPtr instance,int slot) where T:class
        {
            IntPtr table=Marshal.ReadIntPtr(instance);
            IntPtr method=Marshal.ReadIntPtr(table,slot*IntPtr.Size);
            return Marshal.GetDelegateForFunctionPointer(method,typeof(T)) as T;
        }
    }
}
'@
}

$native=[WindowsDeviceLinkResearch.DeviceLinkManagerInventory]::Inspect()

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.ManagerRuntimeInventory'
    TargetRuntimeClass='ModernDeployment.Autopilot.Core.DeviceLinkManager'
    Activated=$native.Activated
    HResult=('0x{0:X8}' -f ([uint32]$native.HResult))
    Error=$native.Error
    RuntimeClassName=$native.RuntimeClassName
    TrustLevel=$native.TrustLevel
    InterfaceCount=@($native.InterfaceIds).Count
    InterfaceIds=@($native.InterfaceIds | ForEach-Object { $_.ToString('D').ToUpperInvariant() })
    ReadOnly=$true
}
