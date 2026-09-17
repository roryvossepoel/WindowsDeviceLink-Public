<#
.SYNOPSIS
Tests whether Windows.Management.Service.dll exposes directly readable CLR/WinRT metadata.

.DESCRIPTION
Uses the documented metadata dispenser APIs to open the concrete
Windows.Management.Service.dll file directly with IMetaDataDispenser::OpenScope and requests
IMetaDataImport. This bypasses RoGetMetaDataFile package-identity resolution and answers only
whether the PE itself contains readable CLR/WinRT metadata.

This probe is read-only. It does not activate or invoke any DeviceLink method and does not
modify firmware, TPM, registry, cloud, network, enrollment, or association state.
#>
[CmdletBinding()]
param(
    [string]$DllPath = (Join-Path $env:SystemRoot 'System32\Windows.Management.Service.dll')
)

$ErrorActionPreference='Stop'
$resolved=(Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path

$typeName='WindowsDeviceLinkResearch.EmbeddedMetadataScopeV1'
if(-not ($typeName -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WindowsDeviceLinkResearch
{
    public sealed class EmbeddedMetadataScopeResult
    {
        public int HResult { get; set; }
        public bool Opened { get; set; }
    }

    public static class EmbeddedMetadataScopeV1
    {
        private static readonly Guid CLSID_CorMetaDataDispenser = new Guid("E5CB7A31-7512-11D2-89CE-0080C792E5D8");
        private static readonly Guid IID_IMetaDataDispenser = new Guid("809C652E-7396-11D2-9771-00A0C9B4D50C");
        private static readonly Guid IID_IMetaDataImport = new Guid("7DAC8207-D3AE-4C75-9B67-92801A497D44");

        [DllImport("rometadata.dll")]
        private static extern int MetaDataGetDispenser(ref Guid rclsid, ref Guid riid, out IntPtr ppv);

        [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet=CharSet.Unicode)]
        private delegate int OpenScopeDelegate(
            IntPtr self,
            [MarshalAs(UnmanagedType.LPWStr)] string scope,
            uint openFlags,
            ref Guid riid,
            out IntPtr importer);

        public static EmbeddedMetadataScopeResult Inspect(string path)
        {
            IntPtr dispenser=IntPtr.Zero;
            IntPtr importer=IntPtr.Zero;
            try
            {
                Guid clsid=CLSID_CorMetaDataDispenser;
                Guid dispenserIid=IID_IMetaDataDispenser;
                int hr=MetaDataGetDispenser(ref clsid, ref dispenserIid, out dispenser);
                if(hr<0) return new EmbeddedMetadataScopeResult { HResult=hr, Opened=false };

                // IMetaDataDispenser: IUnknown slots 0-2, DefineScope=3, OpenScope=4.
                IntPtr vtable=Marshal.ReadIntPtr(dispenser);
                IntPtr fn=Marshal.ReadIntPtr(vtable,4*IntPtr.Size);
                var open=(OpenScopeDelegate)Marshal.GetDelegateForFunctionPointer(fn,typeof(OpenScopeDelegate));

                Guid importIid=IID_IMetaDataImport;
                hr=open(dispenser,path,0,ref importIid,out importer); // CorOpenFlags::ofRead = 0
                return new EmbeddedMetadataScopeResult { HResult=hr, Opened=hr>=0 && importer!=IntPtr.Zero };
            }
            finally
            {
                if(importer!=IntPtr.Zero) Marshal.Release(importer);
                if(dispenser!=IntPtr.Zero) Marshal.Release(dispenser);
            }
        }
    }
}
'@
}

$result=[WindowsDeviceLinkResearch.EmbeddedMetadataScopeV1]::Inspect($resolved)
$hrBytes=[BitConverter]::GetBytes([int32]$result.HResult)
$hrUnsigned=[BitConverter]::ToUInt32($hrBytes,0)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.EmbeddedMetadataScope'
    DllPath=$resolved
    DllVersion=(Get-Item -LiteralPath $resolved).VersionInfo.FileVersion
    HResult=('0x{0:X8}' -f $hrUnsigned)
    Opened=[bool]$result.Opened
    ReadOnly=$true
}
