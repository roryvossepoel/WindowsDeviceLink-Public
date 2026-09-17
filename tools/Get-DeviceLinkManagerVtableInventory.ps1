<#
.SYNOPSIS
Read-only vtable inventory for ModernDeployment.Autopilot.Core.DeviceLinkManager.

.DESCRIPTION
Activates the registered WinRT DeviceLinkManager class, queries its observed functional
interface IID, and reads method pointer addresses from the interface vtable without invoking
any DeviceLink-specific method.

Slots 0-2 are IUnknown and slots 3-5 are IInspectable. Slots 6+ are reported as candidate
DeviceLinkManager ABI entries only; no method names/signatures are assumed.
#>
[CmdletBinding()]
param(
    [ValidateRange(7,20)][int]$SlotCount = 12
)

$ErrorActionPreference = 'Stop'

$typeName='WindowsDeviceLinkResearch.ManagerVtableInventory'
if(-not ($typeName -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WindowsDeviceLinkResearch
{
    public sealed class VtableSlotInfo
    {
        public int Slot { get; set; }
        public long Address { get; set; }
        public string ModuleName { get; set; }
        public long ModuleBase { get; set; }
        public long Rva { get; set; }
        public bool DeviceLinkSpecific { get; set; }
    }

    public sealed class ManagerVtableResult
    {
        public string RuntimeClassName { get; set; }
        public Guid InterfaceId { get; set; }
        public VtableSlotInfo[] Slots { get; set; }
    }

    public static class ManagerVtableInventory
    {
        private const string RuntimeClassName = "ModernDeployment.Autopilot.Core.DeviceLinkManager";
        private static readonly Guid InterfaceId = new Guid("1F79101B-A792-5008-A82A-A4B232229026");

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

        public static ManagerVtableResult Inspect(int slotCount)
        {
            IntPtr hstr = IntPtr.Zero;
            IntPtr instance = IntPtr.Zero;
            IntPtr iface = IntPtr.Zero;
            bool uninit = false;
            try
            {
                int hr = RoInitialize(0);
                uninit = hr >= 0;
                ThrowIfFailed(WindowsCreateString(RuntimeClassName, RuntimeClassName.Length, out hstr), "WindowsCreateString");
                ThrowIfFailed(RoActivateInstance(hstr, out instance), "RoActivateInstance");

                Guid iid = InterfaceId;
                int qi = Marshal.QueryInterface(instance, ref iid, out iface);
                ThrowIfFailed(qi, "QueryInterface(DeviceLinkManager)");

                IntPtr table = Marshal.ReadIntPtr(iface);
                var list = new List<VtableSlotInfo>();
                var modules = Process.GetCurrentProcess().Modules;

                for (int slot = 0; slot < slotCount; slot++)
                {
                    IntPtr fn = Marshal.ReadIntPtr(table, slot * IntPtr.Size);
                    long addr = fn.ToInt64();
                    string moduleName = null;
                    long moduleBase = 0;
                    long rva = -1;

                    foreach (ProcessModule module in modules)
                    {
                        long start = module.BaseAddress.ToInt64();
                        long end = start + module.ModuleMemorySize;
                        if (addr >= start && addr < end)
                        {
                            moduleName = module.ModuleName;
                            moduleBase = start;
                            rva = addr - start;
                            break;
                        }
                    }

                    list.Add(new VtableSlotInfo
                    {
                        Slot = slot,
                        Address = addr,
                        ModuleName = moduleName,
                        ModuleBase = moduleBase,
                        Rva = rva,
                        DeviceLinkSpecific = slot >= 6
                    });
                }

                return new ManagerVtableResult
                {
                    RuntimeClassName = RuntimeClassName,
                    InterfaceId = InterfaceId,
                    Slots = list.ToArray()
                };
            }
            finally
            {
                if (iface != IntPtr.Zero) Marshal.Release(iface);
                if (instance != IntPtr.Zero) Marshal.Release(instance);
                if (hstr != IntPtr.Zero) WindowsDeleteString(hstr);
                if (uninit) RoUninitialize();
            }
        }

        private static void ThrowIfFailed(int hr, string operation)
        {
            if (hr < 0) throw new COMException(operation + " failed with HRESULT 0x" + hr.ToString("X8") + ".", hr);
        }
    }
}
'@
}

$result=[WindowsDeviceLinkResearch.ManagerVtableInventory]::Inspect($SlotCount)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.ManagerVtableInventory'
    RuntimeClassName=$result.RuntimeClassName
    InterfaceId=$result.InterfaceId.ToString('D').ToUpperInvariant()
    SlotCount=@($result.Slots).Count
    Slots=@($result.Slots | ForEach-Object {
        [pscustomobject]@{
            Slot=$_.Slot
            Address=('0x{0:X}' -f [uint64]$_.Address)
            ModuleName=$_.ModuleName
            ModuleBase=if($_.ModuleBase -ne 0){'0x{0:X}' -f [uint64]$_.ModuleBase}else{$null}
            Rva=if($_.Rva -ge 0){'0x{0:X}' -f [uint64]$_.Rva}else{$null}
            DeviceLinkSpecific=[bool]$_.DeviceLinkSpecific
        }
    })
    ReadOnly=$true
}
