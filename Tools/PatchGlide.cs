using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public static class HydroGlidePatch
{
    public const string OriginalSha256 = "006697e503e838fb14f913f845f16d9dde5d4f9d4e27347e3f821f81d0cd4674";
    static ushort U16(byte[] b, int p) { return BitConverter.ToUInt16(b, p); }
    static uint U32(byte[] b, int p) { return BitConverter.ToUInt32(b, p); }
    static void W16(byte[] b, int p, ushort v) { Buffer.BlockCopy(BitConverter.GetBytes(v), 0, b, p, 2); }
    static void W32(byte[] b, int p, uint v) { Buffer.BlockCopy(BitConverter.GetBytes(v), 0, b, p, 4); }
    static uint Align(uint n, uint a) { return checked((n + a - 1) / a * a); }
    public static string Hash(byte[] data)
    {
        using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "").ToLowerInvariant();
    }
    static int RvaOffset(byte[] b, int table, int count, uint rva)
    {
        for (int i=0; i<count; i++)
        {
            int s=table+40*i; uint va=U32(b,s+12), size=U32(b,s+16), raw=U32(b,s+20);
            if (rva>=va && rva-va<size) return checked((int)(raw+rva-va));
        }
        throw new InvalidDataException("Import RVA is not file-backed.");
    }
    public static byte[] Apply(byte[] original)
    {
        if (Hash(original)!=OriginalSha256) throw new InvalidDataException("Unsupported Glide2x.dll. This patch requires the unmodified ThunderGlide2x v1.10 D3D11 wrapper.");
        byte[] b=original; int pe=(int)U32(b,0x3c), opt=pe+24;
        if (U16(b,0)!=0x5a4d || U32(b,pe)!=0x4550 || U16(b,pe+4)!=0x14c || U16(b,opt)!=0x10b)
            throw new InvalidDataException("Expected a 32-bit PE DLL.");
        int count=U16(b,pe+6), table=opt+U16(b,pe+20), newHeader=table+40*count;
        uint fileAlign=U32(b,opt+36), sectionAlign=U32(b,opt+32), headers=U32(b,opt+60);
        if (newHeader+40>headers) throw new InvalidDataException("No spare section header.");
        for (int i=newHeader;i<newHeader+40;i++) if (b[i]!=0) throw new InvalidDataException("Spare header is occupied.");
        if (U32(b,opt+96+4*8)!=0 || U32(b,opt+96+11*8)!=0) throw new InvalidDataException("Signed or bound imports are unsupported.");
        uint end=0;
        for(int i=0;i<count;i++) { int s=table+40*i; end=Math.Max(end,checked(U32(b,s+12)+Math.Max(U32(b,s+8),U32(b,s+16)))); }
        uint sectionRva=Align(end,sectionAlign), rawOffset=Align((uint)b.Length,fileAlign);
        int oldImport=RvaOffset(b,table,count,U32(b,opt+104)), n=0;
        while(U32(b,oldImport+n*20)!=0 || U32(b,oldImport+n*20+12)!=0 || U32(b,oldImport+n*20+16)!=0)
        { if(++n>32) throw new InvalidDataException("Unexpected import table."); }
        int descLength=(n+2)*20, dllOff=descLength;
        byte[] dllName=Encoding.ASCII.GetBytes("HydroSave.dll\0"), exportName=Encoding.ASCII.GetBytes("HydroSave_Init\0");
        int hintOff=(int)Align((uint)(dllOff+dllName.Length),2);
        int intOff=(int)Align((uint)(hintOff+2+exportName.Length),4), iatOff=intOff+8, dataLength=iatOff+8;
        uint rawSize=Align((uint)dataLength,fileAlign);
        byte[] result=new byte[checked((int)(rawOffset+rawSize))]; Buffer.BlockCopy(b,0,result,0,b.Length);
        int raw=(int)rawOffset;
        Buffer.BlockCopy(b,oldImport,result,raw,n*20);
        Buffer.BlockCopy(dllName,0,result,raw+dllOff,dllName.Length);
        Buffer.BlockCopy(exportName,0,result,raw+hintOff+2,exportName.Length);
        W32(result,raw+n*20,sectionRva+(uint)intOff);
        W32(result,raw+n*20+12,sectionRva+(uint)dllOff);
        W32(result,raw+n*20+16,sectionRva+(uint)iatOff);
        W32(result,raw+intOff,sectionRva+(uint)hintOff); W32(result,raw+iatOff,sectionRva+(uint)hintOff);
        Buffer.BlockCopy(Encoding.ASCII.GetBytes(".hsave"),0,result,newHeader,6);
        W32(result,newHeader+8,(uint)dataLength); W32(result,newHeader+12,sectionRva);
        W32(result,newHeader+16,rawSize); W32(result,newHeader+20,rawOffset);
        W32(result,newHeader+36,0xc0000040); // Initialized data, readable and writable.
        W16(result,pe+6,(ushort)(count+1)); W32(result,opt+56,Align(sectionRva+(uint)dataLength,sectionAlign));
        W32(result,opt+8,checked(U32(b,opt+8)+rawSize));
        W32(result,opt+64,0); // Optional PE checksum; original wrapper has none.
        W32(result,opt+104,sectionRva); W32(result,opt+108,(uint)descLength);
        return result;
    }
}
