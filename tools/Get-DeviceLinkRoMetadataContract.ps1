<#
.SYNOPSIS
Enumerates the Windows Runtime ABI metadata for DeviceLinkManager without invoking DeviceLink methods.

.DESCRIPTION
Uses the documented Windows Runtime metadata APIs MetaDataGetDispenser and RoGetMetaDataFile
for ModernDeployment.Autopilot.Core.DeviceLinkManager, then reads the returned IMetaDataImport
metadata interface directly to enumerate method definitions and raw signature blobs for the
runtime type.

This probe is read-only. It does not invoke any DeviceLinkManager method and does not modify
firmware, TPM, registry, cloud, network, enrollment, or association state.
#>
[CmdletBinding()]
param(
    [string]$RuntimeClassName = 'ModernDeployment.Autopilot.Core.DeviceLinkManager'
)

$ErrorActionPreference='Stop'

$typeName='WindowsDeviceLinkResearch.RoMetadataContractV1'
if(-not ($typeName -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace WindowsDeviceLinkResearch
{
    public sealed class MetadataMethod
    {
        public uint Token { get; set; }
        public string Name { get; set; }
        public uint Attributes { get; set; }
        public uint ImplementationFlags { get; set; }
        public uint CodeRva { get; set; }
        public byte[] Signature { get; set; }
    }

    public sealed class MetadataContractResult
    {
        public string RuntimeClassName { get; set; }
        public int HResult { get; set; }
        public string MetadataFile { get; set; }
        public uint TypeDefToken { get; set; }
        public string TypeDefName { get; set; }
        public MetadataMethod[] Methods { get; set; }
    }

    public static class RoMetadataContractV1
    {
        private static readonly Guid CLSID_CorMetaDataDispenser = new Guid("E5CB7A31-7512-11D2-89CE-0080C792E5D8");
        private static readonly Guid IID_IMetaDataDispenser = new Guid("809C652E-7396-11D2-9771-00A0C9B4D50C");

        [DllImport("rometadata.dll")]
        private static extern int MetaDataGetDispenser(ref Guid rclsid, ref Guid riid, out IntPtr ppv);

        [DllImport("WinTypes.dll")]
        private static extern int RoGetMetaDataFile(IntPtr name, IntPtr metaDataDispenser, out IntPtr metaDataFilePath, out IntPtr metaDataImport, out uint typeDefToken);

        [DllImport("combase.dll", CharSet = CharSet.Unicode)]
        private static extern int WindowsCreateString(string sourceString, int length, out IntPtr hstring);

        [DllImport("combase.dll")]
        private static extern int WindowsDeleteString(IntPtr hstring);

        [DllImport("combase.dll")]
        private static extern IntPtr WindowsGetStringRawBuffer(IntPtr hstring, out uint length);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int EnumMethodsDelegate(IntPtr self, ref IntPtr phEnum, uint typeDef, [Out] uint[] methods, uint max, out uint count);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetMethodPropsDelegate(IntPtr self, uint methodDef, out uint parentType, StringBuilder name, uint nameCapacity, out uint nameLength, out uint attributes, out IntPtr signature, out uint signatureLength, out uint codeRva, out uint implementationFlags);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetTypeDefPropsDelegate(IntPtr self, uint typeDef, StringBuilder name, uint nameCapacity, out uint nameLength, out uint flags, out uint extendsToken);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate void CloseEnumDelegate(IntPtr self, IntPtr hEnum);

        public static MetadataContractResult Inspect(string runtimeClassName)
        {
            IntPtr dispenser=IntPtr.Zero;
            IntPtr className=IntPtr.Zero;
            IntPtr metadataFile=IntPtr.Zero;
            IntPtr importer=IntPtr.Zero;
            IntPtr methodEnum=IntPtr.Zero;

            try
            {
                Guid clsid=CLSID_CorMetaDataDispenser;
                Guid iid=IID_IMetaDataDispenser;
                int hr=MetaDataGetDispenser(ref clsid, ref iid, out dispenser);
                ThrowIfFailed(hr, "MetaDataGetDispenser");

                ThrowIfFailed(WindowsCreateString(runtimeClassName, runtimeClassName.Length, out className), "WindowsCreateString");

                uint typeDef;
                hr=RoGetMetaDataFile(className, dispenser, out metadataFile, out importer, out typeDef);
                if(hr<0)
                {
                    return new MetadataContractResult {
                        RuntimeClassName=runtimeClassName,
                        HResult=hr,
                        MetadataFile=null,
                        TypeDefToken=0,
                        TypeDefName=null,
                        Methods=new MetadataMethod[0]
                    };
                }

                string metadataPath=HStringToString(metadataFile);
                IntPtr table=Marshal.ReadIntPtr(importer);

                // IUnknown = slots 0-2. IMetaDataImport::GetTypeDefProps is method 10 => slot 12.
                var getTypeDefProps=GetDelegate<GetTypeDefPropsDelegate>(table,12);
                var typeName=new StringBuilder(1024);
                uint typeNameLength,typeFlags,extendsToken;
                ThrowIfFailed(getTypeDefProps(importer,typeDef,typeName,(uint)typeName.Capacity,out typeNameLength,out typeFlags,out extendsToken),"IMetaDataImport.GetTypeDefProps");

                // IMetaDataImport::EnumMethods is method 16 => vtable slot 18.
                var enumMethods=GetDelegate<EnumMethodsDelegate>(table,18);
                // IMetaDataImport::GetMethodProps is method 31 => vtable slot 33.
                var getMethodProps=GetDelegate<GetMethodPropsDelegate>(table,33);
                var closeEnum=GetDelegate<CloseEnumDelegate>(table,3);

                var found=new List<MetadataMethod>();
                var buffer=new uint[64];
                while(true)
                {
                    uint count;
                    hr=enumMethods(importer,ref methodEnum,typeDef,buffer,(uint)buffer.Length,out count);
                    ThrowIfFailed(hr,"IMetaDataImport.EnumMethods");
                    if(count==0) break;

                    for(int i=0;i<count;i++)
                    {
                        var methodName=new StringBuilder(1024);
                        uint parent,nameLength,attrs,sigLength,rva,implFlags;
                        IntPtr sig;
                        ThrowIfFailed(getMethodProps(importer,buffer[i],out parent,methodName,(uint)methodName.Capacity,out nameLength,out attrs,out sig,out sigLength,out rva,out implFlags),"IMetaDataImport.GetMethodProps");

                        byte[] signature=new byte[sigLength];
                        if(sig!=IntPtr.Zero && sigLength>0) Marshal.Copy(sig,signature,0,(int)sigLength);
                        found.Add(new MetadataMethod {
                            Token=buffer[i],
                            Name=methodName.ToString(),
                            Attributes=attrs,
                            ImplementationFlags=implFlags,
                            CodeRva=rva,
                            Signature=signature
                        });
                    }
                }

                if(methodEnum!=IntPtr.Zero)
                {
                    closeEnum(importer,methodEnum);
                    methodEnum=IntPtr.Zero;
                }

                return new MetadataContractResult {
                    RuntimeClassName=runtimeClassName,
                    HResult=0,
                    MetadataFile=metadataPath,
                    TypeDefToken=typeDef,
                    TypeDefName=typeName.ToString(),
                    Methods=found.ToArray()
                };
            }
            finally
            {
                if(methodEnum!=IntPtr.Zero && importer!=IntPtr.Zero)
                {
                    try
                    {
                        IntPtr table=Marshal.ReadIntPtr(importer);
                        var closeEnum=GetDelegate<CloseEnumDelegate>(table,3);
                        closeEnum(importer,methodEnum);
                    }
                    catch {}
                }
                if(importer!=IntPtr.Zero) Marshal.Release(importer);
                if(metadataFile!=IntPtr.Zero) WindowsDeleteString(metadataFile);
                if(className!=IntPtr.Zero) WindowsDeleteString(className);
                if(dispenser!=IntPtr.Zero) Marshal.Release(dispenser);
            }
        }

        private static T GetDelegate<T>(IntPtr table, int slot) where T:class
        {
            IntPtr fn=Marshal.ReadIntPtr(table,slot*IntPtr.Size);
            return Marshal.GetDelegateForFunctionPointer(fn,typeof(T)) as T;
        }

        private static string HStringToString(IntPtr hstring)
        {
            if(hstring==IntPtr.Zero) return null;
            uint len;
            IntPtr buffer=WindowsGetStringRawBuffer(hstring,out len);
            return buffer==IntPtr.Zero ? null : Marshal.PtrToStringUni(buffer,(int)len);
        }

        private static void ThrowIfFailed(int hr,string operation)
        {
            if(hr<0) throw new COMException(operation+" failed with HRESULT 0x"+hr.ToString("X8")+".",hr);
        }
    }
}
'@
}

$result=[WindowsDeviceLinkResearch.RoMetadataContractV1]::Inspect($RuntimeClassName)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.RoMetadataContract'
    RuntimeClassName=$result.RuntimeClassName
    HResult=('0x{0:X8}' -f ([uint32]$result.HResult))
    MetadataFile=$result.MetadataFile
    TypeDefToken=('0x{0:X8}' -f $result.TypeDefToken)
    TypeDefName=$result.TypeDefName
    MethodCount=@($result.Methods).Count
    Methods=@($result.Methods | ForEach-Object {
        [pscustomobject]@{
            Token=('0x{0:X8}' -f $_.Token)
            Name=$_.Name
            Attributes=('0x{0:X8}' -f $_.Attributes)
            ImplementationFlags=('0x{0:X8}' -f $_.ImplementationFlags)
            CodeRva=('0x{0:X8}' -f $_.CodeRva)
            SignatureHex=([BitConverter]::ToString($_.Signature) -replace '-',' ')
            SignatureLength=$_.Signature.Length
        }
    })
    ReadOnly=$true
}
