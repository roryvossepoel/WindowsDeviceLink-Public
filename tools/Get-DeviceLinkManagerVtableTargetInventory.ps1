<#
.SYNOPSIS
Resolves read-only jump/thunk chains for DeviceLinkManager vtable slots.

.DESCRIPTION
Activates ModernDeployment.Autopilot.Core.DeviceLinkManager, queries its known interface,
and inspects (without invoking) the function pointers in vtable slots 6 through 11.
For each slot the tool reads a small instruction prefix and follows only a narrow set of
well-known x64 unconditional jump/thunk encodings (E9, EB, FF 25, 48 FF 25,
48 B8 <imm64> FF E0, and the WinRT/COM dispatch stub pattern
B8 <slot> 00 00 00 E9 <rel32>). It returns every hop, module/RVA information,
the dispatch index when observed, and the final resolved address.

No DeviceLink method is invoked. No firmware, registry, TPM, cloud, network, or device
association state is modified.
#>
[CmdletBinding()]
param(
    [ValidateRange(6,64)][int]$FirstSlot = 6,
    [ValidateRange(1,16)][int]$SlotCount = 6,
    [ValidateRange(1,16)][int]$MaxDepth = 8
)

$ErrorActionPreference='Stop'

$typeName='WindowsDeviceLinkResearch.VtableTargetInventory'
if(-not ($typeName -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WindowsDeviceLinkResearch
{
    public sealed class JumpHop
    {
        public int Depth { get; set; }
        public long Address { get; set; }
        public string HexBytes { get; set; }
        public string Kind { get; set; }
        public long Target { get; set; }
        public int DispatchIndex { get; set; }
        public bool HasDispatchIndex { get; set; }
        public string ModuleName { get; set; }
        public long Rva { get; set; }
    }

    public sealed class SlotResolution
    {
        public int Slot { get; set; }
        public long InitialAddress { get; set; }
        public long FinalAddress { get; set; }
        public string FinalModuleName { get; set; }
        public long FinalRva { get; set; }
        public JumpHop[] Hops { get; set; }
    }

    public sealed class TargetInventoryResult
    {
        public string RuntimeClassName { get; set; }
        public Guid InterfaceId { get; set; }
        public SlotResolution[] Slots { get; set; }
    }

    public static class VtableTargetInventory
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
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool GetModuleHandleEx(uint flags, IntPtr moduleNameOrAddress, out IntPtr module);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
        private static extern uint GetModuleFileName(IntPtr module, System.Text.StringBuilder filename, int size);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryInterfaceDelegate(IntPtr self, ref Guid iid, out IntPtr result);

        public static TargetInventoryResult Inspect(int firstSlot, int slotCount, int maxDepth)
        {
            IntPtr hstring=IntPtr.Zero, instance=IntPtr.Zero, iface=IntPtr.Zero;
            bool uninit=false;
            try
            {
                int init=RoInitialize(0);
                uninit=init>=0;
                ThrowIfFailed(WindowsCreateString(RuntimeClassName, RuntimeClassName.Length, out hstring), "WindowsCreateString");
                ThrowIfFailed(RoActivateInstance(hstring, out instance), "RoActivateInstance");

                IntPtr iunknownVtable=Marshal.ReadIntPtr(instance);
                IntPtr qiPtr=Marshal.ReadIntPtr(iunknownVtable, 0);
                var qi=(QueryInterfaceDelegate)Marshal.GetDelegateForFunctionPointer(qiPtr, typeof(QueryInterfaceDelegate));
                Guid iid=InterfaceId;
                ThrowIfFailed(qi(instance, ref iid, out iface), "QueryInterface(DeviceLinkManager)");

                IntPtr vtable=Marshal.ReadIntPtr(iface);
                var slots=new List<SlotResolution>();
                for(int slot=firstSlot; slot<firstSlot+slotCount; slot++)
                {
                    IntPtr initial=Marshal.ReadIntPtr(vtable, slot*IntPtr.Size);
                    slots.Add(ResolveSlot(slot, initial, maxDepth));
                }

                return new TargetInventoryResult { RuntimeClassName=RuntimeClassName, InterfaceId=InterfaceId, Slots=slots.ToArray() };
            }
            finally
            {
                if(iface!=IntPtr.Zero) Marshal.Release(iface);
                if(instance!=IntPtr.Zero) Marshal.Release(instance);
                if(hstring!=IntPtr.Zero) WindowsDeleteString(hstring);
                if(uninit) RoUninitialize();
            }
        }

        private static SlotResolution ResolveSlot(int slot, IntPtr initial, int maxDepth)
        {
            var hops=new List<JumpHop>();
            long current=initial.ToInt64();
            var seen=new HashSet<long>();
            for(int depth=0; depth<maxDepth; depth++)
            {
                if(current==0 || !seen.Add(current)) break;
                byte[] bytes=new byte[16];
                try { Marshal.Copy(new IntPtr(current), bytes, 0, bytes.Length); }
                catch { break; }

                long target=0;
                string kind="Final";
                int dispatchIndex=0;
                bool hasDispatchIndex=false;

                if(bytes[0]==0xB8 && bytes[5]==0xE9) // mov eax,imm32 ; jmp rel32
                {
                    dispatchIndex=BitConverter.ToInt32(bytes,1);
                    hasDispatchIndex=true;
                    int disp=BitConverter.ToInt32(bytes,6);
                    target=current+10+disp;
                    kind="MovEaxDispatchJmpRel32";
                }
                else if(bytes[0]==0xE9) // jmp rel32
                {
                    int disp=BitConverter.ToInt32(bytes,1);
                    target=current+5+disp;
                    kind="JmpRel32";
                }
                else if(bytes[0]==0xEB) // jmp rel8
                {
                    sbyte disp=unchecked((sbyte)bytes[1]);
                    target=current+2+disp;
                    kind="JmpRel8";
                }
                else if(bytes[0]==0xFF && bytes[1]==0x25) // jmp qword ptr [rip+disp32]
                {
                    int disp=BitConverter.ToInt32(bytes,2);
                    long pointerAddress=current+6+disp;
                    target=Marshal.ReadIntPtr(new IntPtr(pointerAddress)).ToInt64();
                    kind="JmpRipIndirect";
                }
                else if(bytes[0]==0x48 && bytes[1]==0xFF && bytes[2]==0x25) // rex.w jmp [rip+disp32]
                {
                    int disp=BitConverter.ToInt32(bytes,3);
                    long pointerAddress=current+7+disp;
                    target=Marshal.ReadIntPtr(new IntPtr(pointerAddress)).ToInt64();
                    kind="JmpRipIndirectRex";
                }
                else if(bytes[0]==0x48 && bytes[1]==0xB8 && bytes[10]==0xFF && bytes[11]==0xE0) // mov rax,imm64; jmp rax
                {
                    target=BitConverter.ToInt64(bytes,2);
                    kind="MovRaxJmpRax";
                }

                string moduleName; long rva;
                GetModuleInfo(current, out moduleName, out rva);
                hops.Add(new JumpHop {
                    Depth=depth,
                    Address=current,
                    HexBytes=BitConverter.ToString(bytes).Replace("-"," "),
                    Kind=kind,
                    Target=target,
                    DispatchIndex=dispatchIndex,
                    HasDispatchIndex=hasDispatchIndex,
                    ModuleName=moduleName,
                    Rva=rva
                });

                if(target==0) break;
                current=target;
            }

            string finalModule; long finalRva;
            GetModuleInfo(current, out finalModule, out finalRva);
            return new SlotResolution {
                Slot=slot,
                InitialAddress=initial.ToInt64(),
                FinalAddress=current,
                FinalModuleName=finalModule,
                FinalRva=finalRva,
                Hops=hops.ToArray()
            };
        }

        private static void GetModuleInfo(long address, out string moduleName, out long rva)
        {
            moduleName=null; rva=0;
            IntPtr module;
            const uint FROM_ADDRESS=0x00000004;
            const uint UNCHANGED_REFCOUNT=0x00000002;
            if(!GetModuleHandleEx(FROM_ADDRESS|UNCHANGED_REFCOUNT, new IntPtr(address), out module) || module==IntPtr.Zero) return;
            var sb=new System.Text.StringBuilder(1024);
            if(GetModuleFileName(module,sb,sb.Capacity)>0) moduleName=System.IO.Path.GetFileName(sb.ToString());
            rva=address-module.ToInt64();
        }

        private static void ThrowIfFailed(int hr, string operation)
        {
            if(hr<0) throw new COMException(operation+" failed with HRESULT 0x"+hr.ToString("X8")+".",hr);
        }
    }
}
'@
}

$result=[WindowsDeviceLinkResearch.VtableTargetInventory]::Inspect($FirstSlot,$SlotCount,$MaxDepth)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.VtableTargetInventory'
    RuntimeClassName=$result.RuntimeClassName
    InterfaceId=$result.InterfaceId.ToString('D').ToUpperInvariant()
    FirstSlot=$FirstSlot
    SlotCount=$SlotCount
    Slots=@($result.Slots | ForEach-Object {
        [pscustomobject]@{
            Slot=$_.Slot
            InitialAddress=('0x{0:X}' -f [uint64]$_.InitialAddress)
            FinalAddress=('0x{0:X}' -f [uint64]$_.FinalAddress)
            FinalModuleName=$_.FinalModuleName
            FinalRva=if($_.FinalRva -gt 0){'0x{0:X}' -f [uint64]$_.FinalRva}else{$null}
            Hops=@($_.Hops | ForEach-Object {
                [pscustomobject]@{
                    Depth=$_.Depth
                    Address=('0x{0:X}' -f [uint64]$_.Address)
                    ModuleName=$_.ModuleName
                    Rva=if($_.Rva -gt 0){'0x{0:X}' -f [uint64]$_.Rva}else{$null}
                    Kind=$_.Kind
                    DispatchIndex=if($_.HasDispatchIndex){$_.DispatchIndex}else{$null}
                    Target=if($_.Target -ne 0){'0x{0:X}' -f [uint64]$_.Target}else{$null}
                    HexBytes=$_.HexBytes
                }
            })
        }
    })
    ReadOnly=$true
}
