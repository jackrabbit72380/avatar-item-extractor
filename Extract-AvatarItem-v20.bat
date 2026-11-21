@echo off
setlocal EnableExtensions
title Avatar Item Extractor v20

rem ===========================================================================
rem  Avatar Item Extractor v20  -  one click
rem
rem  Double-click this file. It unpacks the code it carries to
rem  %LOCALAPPDATA%\AvatarItemExtractor, finds every avatar item source it can
rem  reach, and extracts all of them into a folder called extracted next to
rem  this file.
rem
rem  It needs Python 3.8 or newer and nothing else: the extractor, both
rem  reader modules and the rigging pass all travel inside this file.
rem
rem  It also rigs every item, when it can: put Halo's two rig files in a
rem  folder called rig beside this file
rem      rig\master chief skeleton.blend
rem      rig\fp arms.blend
rem  and have Blender 4.x installed. Without those it extracts and says so.
rem
rem  No folder picker, no drag and drop, no questions.
rem ===========================================================================

set "CACHE=%LOCALAPPDATA%\AvatarItemExtractor"
set "BOOT=%CACHE%\unpack_v20.py"
set "OUT=%~dp0extracted"

echo.
echo   Avatar Item Extractor v20
echo   -------------------------
echo.

if not exist "%CACHE%" mkdir "%CACHE%" >nul 2>&1
echo   Unpacking the code carried inside this file...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText('%~f0'); $a='###BOOTSTRAP###'; $b='###PAYLOAD###'; $i=$t.LastIndexOf($a); $j=$t.LastIndexOf($b); if($i -lt 0 -or $j -le $i){exit 1}; $s=$t.Substring($i+$a.Length,$j-$i-$a.Length).TrimStart([char]13,[char]10).TrimEnd([char]13,[char]10); $e=New-Object Text.UTF8Encoding($false); [IO.File]::WriteAllText('%BOOT%',$s,$e)"
if not exist "%BOOT%" goto :unpackfailed
echo.

set "PY="
py -3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=py -3"
if defined PY goto :run

python -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=python"
if defined PY goto :run

python3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=python3"
if defined PY goto :run

echo   Python 3.8 or newer was not found on this computer.
echo.
echo   Install it from https://www.python.org/downloads/windows/
echo   and tick "Add python.exe to PATH" in the installer, then run this
echo   file again. Nothing else is needed.
echo.
start "" https://www.python.org/downloads/windows/
pause
exit /b 2

:run
%PY% "%BOOT%" "%~f0" "%CACHE%" --obj --out "%OUT%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto :done
if "%RC%"=="3" goto :unparsed
if "%RC%"=="4" goto :nothing
if "%RC%"=="5" goto :noreaders

echo.
echo   The extractor stopped with code %RC%.
echo   Nothing was deleted or moved. Run this file again to retry.
echo.
pause
exit /b %RC%

:noreaders
echo.
pause
exit /b 5

:nothing
echo.
echo   No item sources were found.
echo.
echo   A source is a folder holding closet_index.tsv, or one holding the item
echo   .bin / .asset files. Put it in Downloads, Desktop or Documents - or in
echo   this file's own folder - and run this file again.
echo.
pause
exit /b 4

:unparsed
echo.
echo   Error: this container does not contain Avatar Item Content.
echo   Please try another.
echo.
echo   The files found are listed above, one line per item, with the reason
echo   each one was not an avatar item.
echo.
pause
exit /b 3

:unpackfailed
echo.
echo   Could not unpack the code carried inside this file.
echo   The file was probably truncated while downloading.
echo.
echo   Download it again, or copy it to C:\Tools and run it from there.
echo.
pause
exit /b 1

:done
echo.
echo   Done. Everything is in:
echo      %OUT%
echo.
pause
endlocal
exit /b 0
###BOOTSTRAP###
"""Unpack the code carried in the .bat, extract the items, then rig them.

Everything the tool needs travels inside the .bat: the extractor, the two
reader modules and the rigging pass. Two things cannot travel with it - Halo's
own rig files and Blender itself - so if a folder called rig holds the two
.blend files and Blender 4.x is installed, the same double-click also rigs
every item; if either is missing the run stops after extracting and says why.
"""

import base64
import glob
import json
import os
import shutil
import subprocess
import sys
import zlib

MARKER = "###PAYLOAD###"
READERS = ("avatar_mesh.py", "lzx.py")
RIGS = ("master chief skeleton.blend", "fp arms.blend")


def ensure_readers(cache, bat_dir):
    """Get avatar_mesh.py and lzx.py into the cache folder, or explain what to do."""
    missing = [name for name in READERS if not os.path.exists(os.path.join(cache, name))]
    for name in missing:
        for folder in (bat_dir, os.getcwd()):
            source = os.path.join(folder, name)
            if os.path.exists(source):
                shutil.copyfile(source, os.path.join(cache, name))
                break
    still = [name for name in READERS if not os.path.exists(os.path.join(cache, name))]
    if still:
        print("")
        print("   The reader modules %s are missing." % " and ".join(still))
        print("")
        print("   Copy avatar_mesh.py and lzx.py into the same folder as this")
        print("   file, then run it again. They are needed once: after that the")
        print("   tool keeps its own copy in")
        print("      %s" % cache)
        print("")
        return 5
    return 0


def find_blender():
    """Blender 4.x, from PATH or from its usual Windows install folder."""
    found = shutil.which("blender")
    if found:
        return found
    for root in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
        if not root:
            continue
        pattern = os.path.join(root, "Blender Foundation", "*", "blender.exe")
        for path in sorted(glob.glob(pattern), reverse=True):
            return path
    return None


def rig(cache, bat_dir, out):
    """One rigging pass over everything that was just extracted."""
    rig_dir = os.path.join(bat_dir, "rig")
    blends = [os.path.join(rig_dir, name) for name in RIGS]
    missing = [name for name, path in zip(RIGS, blends) if not os.path.exists(path)]
    if missing:
        print("")
        print("   No rigging: %s not found in %s" % (", ".join(missing), rig_dir))
        print("   Put Halo's two rig files there and run this file again.")
        return 0
    blender = find_blender()
    if not blender:
        print("")
        print("   No rigging: Blender was not found.")
        print("   Install it from https://www.blender.org/download/ and run this")
        print("   file again - it rigs every item without any other setup.")
        return 0
    target = os.path.join(bat_dir, "rigged")
    print("")
    print("   Rigging every item onto the Halo skeleton and first-person arms...")
    status = subprocess.call([blender, "-b", "--factory-startup", "--python",
                              os.path.join(cache, "rig_items.py"), "--",
                              "--items", out, "--rig", blends[0],
                              "--fp", blends[1], "--out", target])
    if status:
        print("")
        print("   The rigging pass stopped with code %d." % status)
        print("   The extracted files are fine and are in %s" % out)
        return 0
    print("")
    print("   Rigged files are in %s" % target)
    return 0


def main():
    bat, cache = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
    bat_dir = os.path.dirname(os.path.abspath(bat))
    with open(bat, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    blob = "".join(text[text.rfind(MARKER) + len(MARKER):].split())
    files = json.loads(zlib.decompress(base64.b85decode(blob.encode("ascii"))).decode("utf-8"))
    os.makedirs(cache, exist_ok=True)
    for name in sorted(files):
        data = files[name].encode("utf-8")
        path = os.path.join(cache, name)
        if not os.path.exists(path) or open(path, "rb").read() != data:
            with open(path, "wb") as handle:
                handle.write(data)
    status = ensure_readers(cache, bat_dir)
    if status:
        return status
    target = os.path.join(cache, "extract_items.py")
    with open(target, "r", encoding="utf-8") as handle:
        code = compile(handle.read(), target, "exec")
    sys.path.insert(0, cache)
    sys.argv = [target] + rest
    try:
        exec(code, {"__name__": "__main__", "__file__": target})
        result = 0
    except SystemExit as exc:
        result = exc.code if isinstance(exc.code, int) else 0
    out = "extracted"
    for index, word in enumerate(rest):
        if word == "--out" and index + 1 < len(rest):
            out = rest[index + 1]
    if result == 0:
        rig(cache, bat_dir, out)
    return result


if __name__ == "__main__":
    sys.exit(main() or 0)
###PAYLOAD###
c-rl~3wzr}k|_FDdX(!45R)`XJ*;6YpOtMT(XL;grDT$&co>j`MA#s}0YHg#Ci~lOJ-Qp+4S=LG+
5OJ>?oDKg1o~NBU0tuP`t2aN4~ifgFT#A@S#Ayn2Vec=$tusDOrqpTnB0ryrkJP6;Z1ULfd9V=r|
B#dTuUtAbDWEGRfzOfoYTYeJP(Wa!Sqw7NT(u7id4LN@$VgIAi17LxqzQy9*RYj=TUMe;wbqfZqt
k&9=;OyQTQ;RFH2}c<VBi=xd?;lTm;xM{1(AY@{73s{=<{2>klu)G);;iO2SM$%+ov+Z*Wjz5~on
zi)P}`$36owokJ-c=j;Fcxjju6OK3O`XEzBI&BZ*8XE>rjOroNVy@xYFa1n3QVveuoVHQGvt9T|R
p}1R71L9`Y@Ai&FRKPsqIDMcA-Xt)oMNo)nv5dn-m=sWQvXMX%=c_Cb-ZTq}Fn_|(Y;%RY1uf-ad
<z3vrWr!^CRv9`6nveFPhpmX@soA1kd<=3B_5(;P7s5Mi5V?W27njw=QS)TL0-UrawUbm;-XDc70
+r`?>W3=puY*?@I^Yq(&^-*Sisi~e88q(rpaxTEns%R9RN5lXejwSS}x%kwmmQg2D8K0v~cD^Enz
D7GDu)SbZ?s|jAyy%^$wqk`!Fk_Dd55r(eIxei6V=F<SvE>-gn_b)#&vP`&i=W_{gW3zfbe1h|(m
7bz6jlssNf7mv3K*90nJ*M3OR60j@#sxXicF-6{(Q<*XNBki(PwCh2va{!IjN3Z>S<TP*?nz0Pq@
KH9WIw*zD4Z=Y#8ViJ79MgcwUqI(!_nuLHoNdc(8nA{|Q0)SQkl^{XXgYG)w8bHKwnFd)FL8WDww
Gjg08eW9ZY6L??XkZTyVRSb~#L3f}1i`Ce6#%|2)0|O{*5y+eheetQkCuQtIrar0>MRQ$L=i2*jz
BC}Ok&y%H;IOe-1Ru#5Rf$#Nf^TN=r$k2$0$jlC?MrLf-MUh55a5fftv(te@k0FkYgh<B8qet006
@^Vf}5EF09QWK^Y>X3R>E~XHijviMS8qRXJC=+E`qnhz3@g#2ehru+L(y5C;W9>L!u<9jpEL6Th1
WunBMD6!s*-AD%<;O_;&pp&FogKu}>IBw>Vb=_o>p1B7YgRD$e|&|5$Fn5X62G}j;VB3n(1^6Mry
T7lh+->xpde|vuY<A;m!)#ZO)h%?b$_l~+Z$&1(TUjE1Uhl}%97a!ECULSx2nEvkXW#Q9qw~Os?`
M2k9F0SDDZ%iV(195Y3nE*he+08+VANKI!ISeB}$m+*^e0&|Q3)mR?;UPYxeXSoI;iId0ungY;T4
oW@0R8Tm-bwV)Pfw^rq&siIBA5XR{Fp%19C{DSVLioCFIR9tEMBH@nq3F5G4$KhN*g~}E&Pr!xJj
ll&^O%YNPEMXcd?#^OPr=ZkVF&SbJ4GW_Wf)B;kklq90rTB?-x;VMUP~Mj6JWfUbKO#0x`up@ES>
a3P6B;To9e)Q&jFqd2#@ay@i7iNKL0iLTnVCi}5&0qGCMu@N8)b1c{m?{)bOH_z<uG|2S{b+gm&b
0E3(tdGt9P!yt2b2ZYI^cEva1)a-jY52v4G$H{6z<;~8cTdSAHx{!G8^kP)P|FR&$6JM|2%>lv-0
hO&1Bx;Xl!g~zA;MjjO^KTBsBjFicmBVQ{9r?aF0bGIY<2Ocpa<p@l*dCnQGe!8}Jj2R22fhPdhM
exRd<&=1Ds~rS9^E>R^tu_7F5ku>l~>J|FMxUj*`(LcfhyS3fuev*W5h(LEPHr_D{hu5kXD}opO<
*2qHR`cQNzAnd=ccIpt#o)&z@0TA1d|iGDPUrToBQQvh(N9#o-8l8@)J7z~K5P^guoRl^gT1Hv*e
ooFV!6j7DO=BA~SE-YD#K-&v?#2kk5bBAUoCx@b3Eol<dyelFg@0-f%}x7Dd|QSP*gadI3qUc&gq
ua2g7LL)JUQK{EEsi}C_-(B&rU#%F`RJ>PMP}XwVya)7QWP-N{sC!s*`Jm?u5L<vvs`hnq)Cg?5&
%}3@0Xc`V4=+LV^?he$?h$jSKvErXWi+>2Kt`-WXGMGqEby~iIM&ot_3V<KnPBq$VRvNq6U^>|WE
$4Z*Q7swGd5eT#nD|dF4A!Vd;#sk%J}Wm#Iwo%Qy&2MUr%et(Dnbcb2txyF^qxIXL)%L{}fI^*1X
cM?DLq}#P&Z{K~lim85Rd-XA<Pdbb^%I0^x8S+@(nn!!m@+7P0KX8aQA)l3?Q%^L+QQ%<Mr0VASt
81BP>j2Q8QCXe4o$2ZuFY?^|%QZ^6&|6okougbbr~`&V@Aq`AuG%d33ew+is2MZklqK=d2Y?{sU+
ZyL&bPyyu3!%i2O9q$Cbee(?nf5-LRer{^!(5zU?Z&WejE0PbT<RS<REU>JS9QI#08)!L*4`A3?|
A5XAE#c26QW%)c{R2hfZl}}#--M>^UPoL(Lv7f^AxnP$fD<tU8AgP_T5U)xB0Mb~PlH8hwueGC3C
eif5Md1R&0-OPJcb$}7)L-H+2eM%^R(CVzZK~+OxjWn5=WD-bF;ZwI?bPa_wK`+^Xse5Vg^7zL|G
m9VB&%CkXywpAR+^%hcyAn%#=>SXbu$-I4P(MyB9cV1vdcuGD~NxDYv`;Su~gyF{)5hbqA?E7w3J
=%bFX3P8$QkHrrd-)U~pywDNg-E1&CH`CMrQ7OTW^Ne>>|Ti_e9vCDt9%73=Ye}?j(t;2BxRK4e%
gxt(y<oL{;WVU1XxwiUT+kLK~>e}klqfUMC7wF+LeXJS48V3M-&+d3#Ic+^E++tYqpU=K2LH>lyW
W(9<0?!C$U6=6+6-~F%I-Ip>ua&q*eeZifw1kvdsP5T!0W50e(6Cr)5+7`qS_(YW`<ZO2hU`07=E
xybjHj}-oI*t|x|fi|Fe?vhK14+@0r?K<6YIJs$t2*`Z5L|NcSh%Kk$cUl5Ii1pbI7Y`I9Des0qd
}Zx&rM<5SZ_Zx#u_YiseE+HkZz18UGZPNa@2-!vp^#K#@-JL(fzeFowQV%Jg2pjeK5vPC5#hFzR|
)qdpK`sb=S01DqazKsnpjs_Ao_P!Ppp8mGt!vO+K~(q&F0omKY;$~X*AhYEWrd=LfT3@Ir|DME@t
ZjWRg)afRq3&@FM;}L#K#RT;hq3)9P)OpHQ3E6QJ$4X({F{jO+r}I_v3Hh+$h#z1FrQGf6N?4fIO
m0<E_sme87)XG?s{tFMamoFUQB_Lp{v|Q|*i1`y=T|fVK=3L9u#gvfh5cFTa@w-0gPth#q=kfq^R
9kBm&l-%{&^vQ!?1)<(lEdR8e59{=mfA*$;|T_;NqK9iQ%*e)*gP;r2+i9cpYf4X}O3iTtP&vAj^
V{XH;?57ggC!YXxXqfzVznLA6k)_IcfLcB0gJ3^YdJ+fmtROBhOD-#SHya)g5_JVwwNb-EoclJd}
w!(;K!lgiK_p=b{v_+-pf#G9;cZ^O(cKNrM?Qh@;wg93HGNR7M*2u+w2*@pQY^@UascX%RAi<>wN
W~DqvI0Jp+l2dp5DB_U}2S)%Mcy)8|%k}pkZVqe}3~m)H=8I>-R?qJ|;_^AF_PJ3LeR(L<x6|TCk
Id}0e<T12^;rKxV<mu^W3Bd2wl86uQH^tT9^_+^>Ctwh2E^@4+>fK8h{G|82|=Pt9GfMgnL)KC!+
zhOnf9AQ`KHoi|73&{wnsyUbWcOWsB~s&ENfK6M10B$fH%Nhqz*qp?>*KMR`oCZ0=7@t44&brzVP
fv8kThYs2OwX3O0`oXc(Vedc&0tyA8nTE15UVP|J4)dxe+h=78|US}Ll6>he2<|JbNG#{Iy^RhZy
b0m)QU9h1&MX!a(LK*DEpcg@CVl{`Z~f)1W@V<tR=7A_f-&_qgz05J9wQcVT<=9bDPDs7spQqz7(
WU3uFisicQ%+~9=?xTF-c3-wzdy*NzEngRD5yaBK!;ODqjJ+%;>7&|zE}*HIQH2J|S|oE(k=@1`L
LpW&<jfA(WXL$W^zqL)(JCil68V-IyI%_x-a)#iZ=Gq-$)9$Z5hJNiGc+WlR+MbXo@qSd^XKy7;z
B$<MjKEPWSicJXg_Deb4$C%^iJBSNBr?8Z0$aDjxLxLELIyuX;=)hL;Y16dnKV%`YklCCrn#CwpT
qDy{=Eid*5-H1u8l790exb)ZusEX);l^;m`=Fo5s<6Q?^3dHPmvo`$zR{K+lcMFwkxeqU07(0;`t
8gQ`3|RVWD(jW>2Pq-J<r)_nrA?jNzzK@QK;V*<K;EEyZEj4#;KJ?4$&@gG;#<VAUxghCc))EtPz
LlTn|x%AdylI9@96w^7PJi1t*ZFmy{n}TxAGFrpLw17l)y8{uY58{Lu1(Aa6wbIYX11R>ztDmoXE
%FJ#kH>yX%%i(GP!Lr|VgVllh@~i*o{7_Tl(c&%FrSBDNo})C1tgtSeiHv4fcE(0pn~2itKNxp99
Z|x``wmU9rjsD=Z|x8OySQ#44XY*FDNo$<3sKQ=8y%8kRC~v8ovw4!ePPNIJnCRV-XDDVp(iN9;b
!xbaYB5P>sxXyFip@@DIBqiPIJ|%-66h<kaMJxQ8vW7m8jADUKuxj>!rzmb0TjFmakoON_S(a&~(
?W#Hn8!?sM**khRdm3Rzw$_e89j3XU6Jg!A(rAEVkL#$6pW^#4|`^1#;51o-(YjO(vMYrPHTkW@-
14c&RIuYP4SOMw-ze_mY9B^OwNUa)FBhXMa29kYp+#KjGv5W!Jn**90KBW)zgqD*Y(I<RHE)DPm|
NdU?>~VHCIX*e|?$riHw#mCEqS&*E;+=kT>|5A_ocg_0RPl&jM&?Fe{8PY3sM!Z}_3rRtpB~=f!y
|k+DN9bcq(OgJ6EU8x3y+0+3n$?uTo=c@bI-1`l3kS^n?MnS_u?f?2aXaX3iu7WDpJ&sc+k!RVys
vJ<8mrU+HIj*CJ4Ul99IC>HnYwf>5`PJ7RwFlS(2rNZ#c**Jx`V$+?%=Qp;+Ei!-v_+@2rb!5kR0
YjYlCEF@f+9w+KsU5)`vyvkcFi;wZNPG%WTN8-U+{#W^}7d2Q&i?+*tpF&MOaBjdSjgqf2wpnTXK
!kEt*>E|#3s7+Am>G3vtjLY}ri8zAQl*B?mGMV8L3{d+UEIxVQzcuql-!j~WSb~bvpezv(=7bU;m
aNPdT7$y{scr)Qydm*TdH~dTTQ_2KKJrV=#$<y^j4Vj*LKv~hoYUL2@%EvjW52y6J_Ah%Fo(xb+_
xv8H9qktUY{XpCrC3v#YPpa6Rt#!zA1p?C+IQ%?Ll)u#bHY7OK;>?t4Oychhdk$p;CWvifxo)R81
Q}yqqJY9CH7oY6%ohyW%;#tQmFL1aPNA&wC0B5+RHN<W?g5&?6jrO5l!4Xao8_^=rCA9NnX%<ED;
|YdSjiM^I=8GwdH9*Yr6}QK~?Yoep{@PJxC2DZsr2maB1Ty4(8d!t&Vfr(L=JPzcu_$*KAZ7=SeP
)LFx6&#2P3s~px>iDv62tif7GJFsR6U|eFa>hPI%p}79ibBhOYSdgdHaQMwqE<sDc=N^Bq-yulsr
-*jbI<%9GDw%5Np@_Nc4nN^KFMIHpaN&?};ZunVhl~i=t-nXBszqx3kF?r=JB=Nco%H{;p#z-dk6
Rj>T^cm;$gde76<Y5oL<Anzb&2Hh2uHuJF9fngh)6F7IrI<%fk~iMOMGNU4oCG>Ni&8UO?qPEZfh
8d+0&3dz!qxpBiKFaQy)H2lS3^(dWU)(Pe%;{LFMyAPZT(e$y(1ERnOG8D~=Bbip3ewAv-F0qC7y
KawU~{@-IjLEpgux(->acW>Mx}-U3$>;vEI-t|LBBS0Gpbt8)iq@}(z450xwgEb*X}#wcze7>Uo+
k{S1eY!`o|+b}u$Jzz7Yx5GmQ$Q31be7gl%`>&y~O*qL?IF;dp)P5%D5WfPB0y|{K4v?L=^>#3uD
SH}m@Ul&8GRnw_5-&O|qtFocxV02-;$Y9yc^H1GGiyoiO-Zh(c;Jsi&1H}9sZnUCIO|cB-zy2bY<
M2zK~ZGoTHPFsS<XelzU;1Z7ose0yaT8^h+Foriy;;noN{G^Eu)f@N~~u}E*Z6&_eafsk+qfJGm;
98qc3QMIClfqQhuSP)N#PG<c(69xzsQN3yoBQRR_e)4hQ|xU_cl&uzgw3J@*0i9n6JynPbAI_;rQ
%S-Nz`g%l+ZzNuE*$olif`u9%#xvuXJ_U56is9W&}``)MPd+G+t&$V#MTN^fv2F?)Z&$<Lm0Q~dm
HUw4zU4~bSj*mOg*IoH>qCUDRBT@p^7|*ZOy_88%z;4V3<%JzjxpnEAEUXV&p%lWmSZvK7%t>D%;
I1THTCTKprK25i<;%NmFU=?DFQw=Ki(R7B6uSl0{iI#xU><eF2pDX(s~wk8z%`fHJ|NTiee0066)
dc!V`+JN1qr?VOXheh5ZW#wgDPDEIL}ceEy-p1^mMzu2Ag=Idf`g)<|Z*IhS^5qrD3{3hGuMtdgX
8|x1%{39imz7@-Uy31&hiON}o;Bc~Sv-%W{*G3@!1FLaY1zT4~%8%_w8rO&Soey7tWtHkGY$t@cf
?#?pl*&5IQ(PlJSR4{qT6&qDV3XSGBzPggnlB`K<dt~`n5!buC<Qf@KiNvUq`N>T)4C0r2Z1x9=y
&Y~jCY!}Xa0W1s@qT8hTx7=t+0AQeua6z)+o3`Yn104d0;&>xIu98n3%i!eT$8&LVe0)gT!a@n-x
yAx`w%allux6foYb(1%izn-4I4wv;;~n;ampwvDgYJmDx=1tlo&3+5f{As1In#~p_KRbzqI!>JVw
Q%?+b?L$kN5(kr^iP3p0+b1kA!CorlmpE(u49XWP1}7<dp}@GflG@9AKz~M@<~7<7t<N1ztl2Miu
Zy8xzQE-VxVO)bwZjimzzvqb4G^;{oBCdPq3eqDMdeB<S)M*%g>0CR;|wa+1bA4!L2n4;^*Hdt+d
tr!bnl`apC~S0xWxwzQCwHOXNONi-;%E9@;1GL3|Vxx3lc_kb<3kuy;z&m%sR^?N5?jfe}2DzAcV
Ek-t>ZDW!2NM0N{IjU<zflSHMzug>siqO#uuVohc(kOh1=;0Fa#CS8n8STYE-yHC~unvF1hHw)21
pofNpH88iQm=nX1o;;6f$#r*=@jqjGRgKCB76D8Q>0491o68&!KTB)xc8S%gLuc8i0Wmd7!W9vu<
lEwxbh;(i8xur)3~GH-o5cm&*6lwYhx+f$=b_X;;^rMpvm%K++bApy4qSsLB3AEyPTvC%>`|C!lf
3gd-uslyf)-Mlvnwkr`-1r0%R^vg#w}IBjGK*pB<!ODA&J3sgeg)|DN3D5RCP&zY^ae<Vq)9(rK{
k8PBXE-f)D48DDZneaG?Xp^7hJUEtsr50Cn-qoclNVOXicsxC5?BiWB1f=!O18Ak({BNvo~iqyMJ
N?SBnV$O-wK4>kaV@tC`w-}ZJdqDlrT^4SDXAk0_(qa}a<A`nE6bI$Q_b-G8+XIcw{X<j(caMQ<K
lMA}l5ctE9Ek$s98{*9PN(q-9kidQ$OAxu7QkfSkUoY%l7B5`LG}sNTbi@W@j5i~Wl@rZl_BPInS
dj9r0^?^Wh4dFQhH0P(FS%+MfM2f9n!*W3>_JO^+ca-gwD_8<FJUPS&CX26%!&y_$D%<N-#-fy9v
O#<LKrY?G=TUxFT`PC3<0H*VOD0#n{xTV}WDPvJo&fQ9?J2oInt45v2<peD80doXzVRL|z3^FAJe
$m@R=t2i^xN6jEompzBAylPAcf9*g`Rt1$d*>hA3J9_Fw<q&j4TT8VC_*Xwk;o&FJmH>7<fZi8v*
fRbVC9PP$#F$6n#f%}~$5bWAB%l30xq4SCL<lc8z4XC23jV(EEiH@rG%Lb}~d(aGqLZ`Nlh(f_uk
RBiu92hVG)}v>`dsi{+Eoq5AbszLj+$a4b^~9Z@97oxQ_h5D6ms%wG>a_Z5JC7jim7}V*X^c;+s{
Gx;rNIjz>%E&_FpHrNpe>?(BMx_R4J=n~VH&s#<4#cRdE7g(s}OPkad2xZTH=xkV<M)BbvK}-;-u
sW9XA%OAVJ<uf2nx8DDsV^XcJUQz{X*YxB5zRro;fNFO_19{aA)SRSHPlCEp#no!lalKw}a4u~I}
rAB)J3Mv>n&@V*k~w?)XVjxqXy;uX`DqvAqex`^dSPsQ&j-O5OGRjt|nb}gy*^_gtyn?7IXnoKUj
MVhIbp7P-q1(-E3^E5$kzx~*8yNs<1k{+u(T5E*c>)Ft-%SzWn?bIdxxhlwic<53w1rCMQTm2z@O
Fx3)bcBwoGibc#qg0%sc~M3_8FoiQEjdX;kN##|O5yT<niDStMhm8Zvw5l4M}@~&qOwPBd&{7h+X
{XPJVYD~dh()`l<P^oS(NAicg(l)WrA6lPqS#r@vA8Cou%rh)BQ}Oc?Ub}%%TiC@YMHUlH*@vNQM
*76eD=ef`Tq2=_<JKJ!}>wN_qR5HFO;cQFY)qo;_9*yM{C#-$rl@jD5ecBPXhfY9U-ld69d1_%7c
@q3`hWcv%FyAjvyS_@4I}P|M=BeTs%e;I?k(HN4*}odRfaEFE+n_ipFT7U0pMg)yB<`y@Z28+Yl{
cf-xFLnL|s4$&_eJr_qn1KGPqx~$`BgbA?B7zfbf2L0ca%Nrh!SDU;D7Z>Y@yqi-|1)e~nA|zGA#
s5}d?4u%`jw$LG#`vR9Qc}Oqc#N|g6RHqO?uW>l=#uYzi(|B5xBq_i?ycS9LlzZ|sp|j7-~W5?m+
91*`0e+qIHfU{8>kr#)gC&yk5t=J&!l|=4e;s_9asmW`i(>_{!i=+YCyVlX-sS>-7`)_Eg?EJ;J%
>vhH`}F<z2kVjQm4FKudHPRS_2I0nSbGI7!r((a`c~tC=gu<9w8<e%0(c0$p1utSV|l9_1YCERkN
)_>YmD2Brlub4Qa?8?GEyQdhP#f*Q~O1fA4j<L$hYhv6r$a`#xSBD`mYo3Gv|m;+<9T4u;$ddrqr
Eyox&$EHK?DHbfo>tvqjm-cF@U2rH`CWq<F=Tc-3R>eF;ebUcRvIXUXX_n?78vJK_2E538V8;8z=
%Lht^p}y*KBaQP4EbqC`xIV~Eyz67B9jG$vt)Zch5=Q#87UTMN4(%Tpi=5@M>$55lp#zg;3z6;kX
JzOp&Iub=zP<npdY2TwFDNL1#S-3_GM4$vw*G+P|dHe^SQPTR)F4Y?|x4Xz*sq=^5b;!(PPAr447
WTGa8gyO7tl=S!x+vqG$LTlLaeEYIs4atQb%rAkrfKXhwKWUxt=^Wl|DsTMu8iKQslckweEyXdCF
M+bGf02@YqE@?JdZoZObbcu%TEOc|A2O4X>e%;YG04X500i~P2s9$wJzx5S})v^Yb-_=o(%gOHId
pn+jDY6<fzhMK58>W|C;^Gm+8Sp!VJN<ElxJnVb20j(hHf}!7FOjRacG$|iOBcB?$xCr2V8MYHBJ
jyyM_G;%myIbK^+4uCuGkEQ@GOBf=16yN&BhB70%_S<Ul@Z)SCz#E~fovLv%E6Rzj#>DRRg_7)1m
1Osm(Wp7kma2%Qt#MgFqOmQMb)uR>;9Ad1)6^YsCVu<WpE@A;+A1R2PCkccNk{{)-Q<to#Vl{&j)
%&v`8#bBg~K++u6cuNrBOb^$2f+Ra`KkXo=}OMGQLg<oBC{4gdMPjhWNaWd$>fZEKD-zFGpV1GdR
?VZD2P9CpA0I0<9p0#?$Pc^t`D*ZRup*SS!YWgpORPL8|O75%}^@=|N0I4zeU$5Ir?Pu&E;Yf+5Q
u&ZfVfg-@JQ!A>e1<)#*$)lO#`haRMTEfOBs)0R}0ZxNB9@l&P5QBsK33hG@=5dNPACp<q<F%P3!
`!Eah1`j}1ZeUoL`k4sOGhk2v!B@kA+VIiZd2zn=uDMiRTqXU5h3(tVLB4(s+$8>H-a9u4}pxf`z
JZKcm}hfHqX?w&XCA9A?qWdZ!jA%n29G>&u<Rip-T;-eBGeUyVky?ew6kySi}jRr{%;*!-6*(;n+
X4?{1Ut2-U3B&$_I(8MYmomz<_t?Wz&9$Rg(^2kDzy^2b<#+A&ycf$3FQ#zfJus98K7#m<Au(stp
1of_qd%r_Y7uCwS(qz+yBTC)R$bW^7Dcu_*r1Ev=rso}Noiw<*N#VEie93z7bP=z(cH2xAT)b0SP
ZGfj_+|<jKIfEA0sq#2#3J+OY5G_>I<v|=_yfQ?E@tFC`@fgqL@mRB&d`#aY2dx8;&oUsfV;IUJ-
zWLR1y@j>Za+`bwKzQKszaOFVfi3Hk22uA?^dC@_u9tS0tI=#R{fG9>m%Zkx4vw<%_sCFlx^SlyP
XLgk+3=E6n{)6S|}b;6_gvGzrxi?qJksAD>EmaHV-mF{UoG53e11Od<XLS9N-&-(vDD}?2%H(0HK
@Y{OaZ9C6-#QG88KY(o+d{0#3s4^3T;}Z9o7h5G`nazoaV=?4`4Q9HUK^4TNM1CQ!i;$?{AAR&`)
HK?hrUiz6W{#AwDaLB0o0P|VX+hN2i+LRE-GA(t~Jdoff;L8nZef%f?P6W&{preA<qE|w8R-Jfj4
9GVy?r0sPWR<~)4Fjm%k^_2p^MbiA-?}$e~UR`{6|KZ(tm#;4#-N1jZ(uafs{K%;Ebw$GbQ;|wZ>
ZrDjDe(ldjpLdk?~?FU7Tt$6U7qYJuDXYnM!OIJ6yvneGVnZALJ|&&#(Y7i$nS-Rz>u2&WJr)d2l
CLpNuJ%UqS^Bf>>xOZ(IEeXu2!HORJDgM#S<a92xD7_bAdTo;;?*plLT>|;<f)zxs0e5uF<O@qPz
wKA#|(DbJ1>RX-W)b9tIg2`qM?oD2FarbfYG~L<_iyQi{ALW>G#(39q0XV3%XQSaY862;>M6Cck2
kqF+m13*>1!fev*-86<;@iF8sBbfk_eA+Hm8WaX3qhVGB+-EXmREn}l7XI25r%dK&$2$h%y<#l<$
(#GwGD>IT@lxv)>Wn~P9{W9hXkMq!V#olrFVLwcHIBN=p9^mQ&<47ToN+&NyOFC5MEp0EnNu+CM%
S=5YU6$;eBkT_nDKenQ3o^qLfR$GC$2_=GUUy8@g-iactkPFRUN`^+(TtX=q<4Q)ThDk8wbQJPX#
5=g>k$WVAIQzNwZ25=R|DLvv(;j0KS7sjoYp(G*2sy0Y_x(BmmkV7`h-U*pSQx3(#}Bj7tVZLbMn
z<CvsJbavzcCptuFthtHs==TB(3PoCk1r))g3sU+Tr%UAzI#*&P13^IC57ImV>vs_3HKUcyaMp4r
PilYVW@wa8*qI4+&veCZf<3klp(l!wqt%~NjfGJ**#OJCUgHHoT5($&e8<*uMx(P#z&!f5_qQu#r
MVV~1+_m=EEbdYR^wqQ2SIK0wjKk2?EClP5NnM(R%9Mw@3*j)3;x*m9Ysqci5_e&W0gpFkgG`TUx
t6d5?BcXUCWI~-;)Vt?Xw|S5xHK8C6b{2iww!_?uRyHo63ONBmJy}}^pVjWfs9W4=*Fd-uT+_%@=
T^ecrTK)7rA)P`{S^4`WVl01Y0(1L&ai4G9~Qle6O50^B|wc(PU>1oUE*p&sRkhyXkN)-@dx|nSz
_S=OPZ^^7`V<_~Pg5i?>&o@7`i+8{k&)z>_L)sZ4<-zxt2M_hUdDPJaV}%`6-%W{%2^$IHzWeW#F
nrOJ0v!JqDdy;ttNdMj7;F*gVQ&xebbzr1{X(Rp$CmW#7AC4Nd{yrgj{vxHG%o!@VgH|IZ(UtPSv
{s9JcXxZuz*FAOgjsfY<(Dm1eBPC&PCHQJ-E>vD);2no7q}~dl+zEfgURN5&<i#^($TF1)9Pmkx-
L#YF;!12X3s&32=moX*KeZ<4bq0?NEe3HM7>HB1GB7VBQRL#P6|$K7+e~`a7?gI?hP-1IB%-&G)q
vE&k&0?ur>A-!5+mq}(ML_tRaVtEmXQt_j3^gbhAdf*PwO1w)mWG5lCm$<M|icZQ+94SQV+<4d3Y
#HLOBbJQU564buC3nxeQ(yrM}Wx={YI)oHGXU*JRRHq5MGTR%}8eL5~vHvD!Bf=HSpeiPy~;Tk;h
pBNQ)*6}V2*I49<I$y~5Hl{#8I{U^AhXhyk=2}I}F7*EyQbMBXtNeM+cdC1}k+7a(4EF@4HIK(*@
nvO09hbyegpRxVtm}T$G*ey%gbt_c4-yHl`8Ji79jr5^}G3{d`W}nk9zV>V0GYv@D%2^6w2fNEk3
2cv&S`yq{R?Bz?UpgMAraQWk@@)GQh8&<R&7!*q#WRdR1ZeqRf`JW8C7trK3^=ygO1hxu(h(V%sG
M?2a&rN40T}Zxh>>gB5UwCoAbs5#Gs;V5qyZ`&;|uhsFCHSrPv>EnI7(#V`%omqH8+io_`FJa@v&
dgPpVQ;4hX?z2ClO>NRY`Yv=zh2#^ZjVBhul>0d;_9%8DET=kbfj*hd~N*&mLdMF~x4cUM?Sd&iX
%(D{wRq%>4T`IuQUkJ;W9OW%fH0kb$ritt6%K8q$Ls{@>-f=~_%j^1&kR`-X!k?CmQvPY(ppGQ%S
6J;+s(wruh*TrC#tUJ(G>AlHYn}jV?IOHrWfVhq{SO&zWsO!keTNH<>^nS?mFQ5hGk02+2ChY5EA
frc1Pa;Hzbnxn%t;e3OGTc2aAkbMZSCX#N=ADNi{!}|8EIJ&ZKTJ+Xp*N$ZNN<7fb{vW-$eM}5z?
_m172r2ho*|mSb&hT|bvg8{lf`=<8eG*lL)6mqGojhmI@csU+hH|QQMng1Ag#?{TLMrtQFlSOxW7
+-t0ejd<&7KGFoo2rjac+b0+H)Fqv418VnWHl$?eGR|E#kgkAJ?uLq1SOd<nJ`@(#53W;7#zJtX{
hDf&#e1RFu6S&o?;SAfzUHFUEAWbHQKK#-9?@e~D?MBcL^<=po_UcTb1L$aF<M(si|xFs)*Ylj;B
j2xfDOKMAM(Tz+#*y7i@)QjKhJ7Z-sSrtZF$@#A@f4aZ~A@>+D;}deW#&BS^-^yXjdta)7UztTjt
0`U*{#7ab4$<`|$;lt+@hv44rY+Tb(x*3kn*^=r#%&Ulf;qwjo$rds6H!;uPoyJz>0np&lxXk)gl
EXMqiYRbFAGp>Ox_cyK#xNwJYP)dK$GfAX#nT6olr<o0p(Z0#|V8bDiO?dyypya$~+TCgSs$nF5R
V?fH*B&AO|7YMqcC;af(0n^ryc5<VLxw7nI8NSE1dgKkHJ6J`7+r$1+h4#R`;z>bU}sl$_|Y2?<V
n&si?^5a&)#kj}2;{w;gCq$9Fsc_gE5e_U4gu*q>Wt8)MDj)XP7=Ywg>KC=#E4kmzF=MH`J03ZLi
H|)0m7PN2A+ux0TJN?~nBR;A@SVN~MKv=JHm!+$v*YjxsID9j<OrbP6!j769?A17&79O7nHOz(#4
UuY<CQ-3cr90sK4^320%G%a6%bjSbDoU;b4<lzh3XM6+NrmfD5AfI|!9~{Q#ET9iH&iRwYFyfuzV
c1U9J#TPVcp%Pm*C=x_PDV-b>CifLlU<r*%RZek^Ogwr}HZ64GGOMRJ-b-+QE)nZMD--U`O{a*6C
T!BGp~v`mx9fLE|XpAj_y$XJGS(Ee=Yb^Y!$4*4pA3baBmXO9sN>xOZ}=E(m!vE_UEk8#S82Sqn;
<fxm;?u#?;*R6JVU#yrRU*QRqOn986+w{V`KIz`!uA26NL9Z(>#vWd(-drc1R=AcKcVas+NQq}Lm
0-a-2{eN+H=sq9Kv{!+_gDF3%>c&v|N_A6mweWft23Aq8Hel=@5$5d0)MICcn#N4S`t#UQ%?fgZf
9EwP>oUw(nwM1|AG+?Jn64Up5qyHiROzLUY9ipO-oCpYpZ|1zeg1*e{CwK7+D_YOONE4dB-n97py
viKm`TBg={Q73RlKkeBqY;!*i0dPM$w!$zD2JEPa0aQXQ{H};A$>{Y@_w*`YvH<D6*JA9p8aI)jB
w{C_=C6y^@uyG+9z@h1oE}hZJjXIYd955w}K8B-FQzr7g<^>#gM+Ut{*4EQ6<7S|}aw-O!Mdxrgp
~lE<t0O5MwYciO26AZ?W~ue=g-DMx0OF?^v0w70goXw|~oZjZyN$a}JDkD6QE`^_u0x;K}J?%-mm
U**Kwb%v{NEL!shMnK-cDGQK~#&BfU*Us$J!m!TAy>_T(0L!m<L(tWUme`2Zav*L)*q0a>0(K?_Q
tWEGJw+Cvtb1rH!U*u9*E#7}Ye|@h1Cr@g`K1w4e-dP&^i$wVyd0>VcA0y27~XH{_CxxRv{)QUQY
SMNhdV_bQpN$v3N5i-q1st{Ad!xg6x`C6LPp8J+=QG<(9ln5-{rQB;y|Pe2^qOZNe2_scdCRH<(Q
`AN0yVqG%DDpT2_$K9fovErqa)Z1^|tgUK|)+zamW9!VN|5z^IpK)^JlZR<6vdf`-osHK62A7G|i
3zJ9+)1lQ`dj7mvb=Ap8}@MYanU#Z?Ajx@cy1tuS3Wx)RDBGPn>5lwq?8l8E#o<(<IUZ|VYsx~Ly
p?Y=Hz4^W{-)ABG@~RghDZsA|1x(gca!dL}Tz~)JiH)W$@o_b~W4AWMXqL08B9^_tH5!0PlW1?uf
#31Hsv}|xJe{VlRc3*+7yjLqE5gdwC}Oe^WSLI9C=ZRDY{TUP`D-MhbcNvU#_9Md*{wP}$v`GuGj
iJLuws?G60}xqkC!aopiD%GAW`o1Kn_PL3|5R^e=`ptn#J!`YrMiqRibVgw3`-fjs{<?+Wk|tq<)
3ok0!Ag;Jg<=3^>E+B$Q5_S!hv0KpIT@TDPmW5?4ziQFW@Zlk2t%h8;$f;GI))VD+{1gvLfCfR%?
f+Um7Gtko)an?(rZf|9=WHx(?6o{}y|-3wLEdZXX@%v0{?+`woT@o|0Z@N%f<ahr#ux+V#RavbC|
FXgRLw$QHY6$pPN&NZuRkOj2LMe5i|Qs#nr;oFKqre|TqtZMSdm&=B|Qnc{kKCpA7oF`&my+<UHj
&E%@NW=G0wdT4&O4A`4*)icf{3U5{fnLP08Kh?>%@e5>n}NRI#8V!Rf6Ad(-L%_5y$i|rI5M|)Kv
ygZCqT66i_pBV|MLf^yR-E<8YHM^(dr-8zM*@(ZRkV*$*0?_oO2Kqi-3~xc%}{re;)JwAv|929Px
c6Ay*8f+>t3j>vl;(r`L4bNsjYRG~j@+3>@{66AbFxia~aFZ@F>pytZg&G&e6Ws+$q!O^A;8yX2y
!8b<kRYrlQb<bVUB3EooXbI5k?FP(99GrKNDD(7~@gX|717yrw=`nMwvro3&J(o}<ZK-`A3I!niP
t>!>Q!YU7yBk7KDVZO($gVKG|(y2~sy?A$Cn&iG<)e3HK%oEzL&wcM?ZojZ-xD#tXV)7f_**Zv4^
%qd}*pVFrMi1~WgZI+;c%K`pmUpt{lq?TUzB3;=PRhH6Oy0{lKuQl5k%eAK=^7w4KFzz@RnE@4p<
VTZ-qkkx3hV)9HF$RIBE#hufkyeKnPZJIioj|*gju(ncHU=2Qs!j+<*Q*D)9Lz$e8kk+@SJsTt4V
u~;b0@3m@&~-S-_0VM&Jld{}Ct9uUVqj?Za|7;frzf4Sh3gZ#z?2rmn=jPE(5SK*}@wLfXKxpqjm
?F}apmeN#~0u5_HDN@!S4I;yp*`;;uv&`mW(m3*NtZ%MCk%7-JJ^O-Q^@-h~)v_WG-l`BjLq+~<N
;wROMNR92hm%&20z4G3GC`YznN4HhN?wqa0wn~ppS`B$)<axDo$wM4f*W8Y0EFXSHx+$f7XUIPS&
>yG^n{qLHw%q7c?(!*x_*Ut;apyUxqwd}%I~EmjM+ol`@G;c0vUW5Wb$q{JdMYMLK3BKY$rYWp2Y
xc#v<ctwyXyl%5mG?7vq&rv#cic6q6sBXf<W&cE<hHYar(&&{9J$8)vT(A*w_HcVc1BLj%f%@Eve
yGTT-kiU7#}kjzI8n!U{rfV@WOa9cgqIM6EB18=>aU>8ZZpZM=|IgU%SB2+YaHF*~B2v8Nrq?V1M
BZAes_#2tftg{sJs+YnI6x~}QI#UsNzCy1T3wy>&k^eeLLkTfmTYQW@jDq`c#BwjqjytZ0h%y$V{
$89IMs3=|(*8%JXM>n|dlR*n>Ypt-~a$8b85jV=(-z=J<3#q&<#OZbumHHx}D8tAZ<Z6jJbt@nZ*
78A1d<r*baj=-o0+m>r5`HVaCCAb_8u>Emx8Gp!-|iv7QR(WIR<3)!c*i>r*f@WGcObc6`K}qlh|
Q|BaeVYFEMM0&YQ&E;eF~+7D4ln4C)M3<kQ?LinVE-T`*2lr$WwWx+e<Bs9K*AzQMNT|OcJUt6Ql
@uWLvqlQwhh%^Y<P2m+F>{4A7>2xiVK<{%3=CRblMLZN~KI^0qGS7oyg#g@yfz0{}V9XvXGqFQAR
%HmA3xj`(KoTwg3!d7*BfDAO%@tUKYL4Ydg}RyZ|jr?V6)RbM#c^`O?8Z?>$kvNqVoe#qIp&dxbO
cxrTBSqZ*E{Zx^xmjJ1B@iL9m>>6c>fq9u%<scx^HBZwVOSIe;m8T{U;s;p11u)IgG7dKKvLwe6;
GlK%lp^p33zY}JZ4Pf7Qa`B1C?d+K!*{jI!BDV#fqKUP<MuC>L3EcG5f0o$!zsqtq0{v@*6*^`*-
-*l6x6@FV>_>&AJP_xgH`Ed$P~i*Tr>lcax@P%Ze!|%G?OXat->7d<BK=%kzc-gFNwG_Bb5z+t~x
H3%uznoifo#zVkeiBP4U)!Q_aCEkF7KDTNT5UmR^ynx)O;@)o$wMY73S}5k-+M52m`pd{(jXdDc{
j!WKZ0dZJldMQNx8m1{>-hbPc!n1QxbX_Vmyqx#a?f>pt=+Vb)?+mt<8%zE0$QQwa?6zMvWnz8M*
#Wt`8crZ$-Amw=TzOI<vyrDa;EsgBymb^D0kfAE7_WkcQhip}`Zum9ljl{EFM6jHS;eA-RLWv<bS
Z;`>{;V3m;6rKbP?=o$mer=MJu#FQMvL7qYP>G2yhCWdD8u*gU~3~UZW_nMn|mlB&Q=G$Y5pkZ2?
5U`XW5X=SBn@`C^zI+l7`>23bIJFlr|7#PFBgMBz;I~#~<D5mQ2G}Q+nl6ysAfsX8wzN@tgR&CJ|
8=gXdDjuE@7_G{%s49SmFIM%?ZuD49&7&!&9Se5byHvIqHF8dX{j!k6-G&2V;M7H@WmS`_vGP-`i
ry{)LlQY^1l-I-)Wp~tWFR}-`d@kktZyOff5Yh*X&=h^9W4DU{ELt{W0QtHfheN%cjqL=cs?a9SL
Hu){Msz<qA^<w$RYDVf$1_~0T?^QG1lFAf2mW9TrQZP`2WP6CtinKr>r!hW?r+aA0QXB{{Db9Ktf
)%})5v!1Cq-M~y?Bkhh(UP<Do%%wDQp=hAlbbN35{KBJ2NXm@`oo&&KzGbJ76#R6l?2W&HA9jsAJ
j#3!#s@TRa?csdnD1o&cU_Ck2FM9$jLIY`8b$_am>nT$$OEWSfvfn+N4P3AdqBJAJu+&e?c{7jC8
TI+>y(6b;r8lq0#7wqqreg={HOpm{VRl&tT+z0{4}E#XP#?+Wp#4c8euPHdF(`yN8RV0e(fQ8{r@
E)kj*%f!@Zdn%|@hQ65Q&?qN9Sbw`a_Emo{5?5sI299pCYfGK*rTbc#pLpl&bW#rKm_LnWR@nVv#
tCZXhr9M*nMf_rF7SHT~4EEAwmxrruOYgGp3-wCU!{NTM|1hFNh~XMI2p~rRj6bhA_8&Wfp^Ike>
=C6P)^WfHzU&i6lLb1negeS}YR)=S%Al3Aw;cuR<vC*+4n2iF+)mtG3SgRRx7Ut*okSdpMPB1ojx
nW|rohO2r{X`N7lOQH@M@ycF(#td=bSSv3vxmf!2O&u&guEUWc`k~o^yEG;3k1(DdxAUSa2wuTWN
ort;h^m&iKhXOrikiiU+{mDu!9Y@JKYq$Uy}x0cIJy4`O--l%~LtesO`mM~8hH_5;x5^nu{=0#n1
8At9s^hEj>k+`Hr-(>rNTA`HV+6mi(*?DQBB4kLao(j5B56pYa=5I+#mC*&58<pqZWTS(mydc7g6
sE=|KI&RQ+AI{%gjIS>L^8!QP^q-!b-Xw1>-;Up$U%$j?IQ^UC?T>H9FMl|vh&}z|6Mpdi!{wXv5
5J6GU%dVP`UiaVlwVw3ynOfemHn!J^tYP?zFwcdcnzJMe|K^H3p_qKx=DWc@w@M!v!7pFUSr7~H2
?m?#r21a3w(O@%bOSPUQ-j@@&z>`E1Y2Pp3AqD=e<7l2m`1*K7W1r{o9LI*7K*dG8h;3`j__?<IA
@{L8(`)zAqpDbn)TE`Ss-+j-FmVmn|~5%Ev#xefjPU4EpMd-qC)2|L*GY`tse|@zv{h)U$^P2{E7
M;Su~hfq$nhaRlFw;rR)C|Jx~E;e!YLzv1P`i=VGQoR8(OF_4Y^>CsQ0eh%s9h<=Xg=Y)Qq($6XW
xM#uNTKLoJ%6~oiuP^@{%6~`l-?996B5!yq51a916~(i$%6d6QHGqzj!fF{fYr7-y4Nj;ujTk}Jd
puW*T!xqvFG50W-x<dj)tj(n?XaWYhH+W^@T8$Uy?^pV^zDvnL@QOJ_teNig|iz*lqZQkVsj&OmF
kIS&$x<B(+l8TLQh3kv+(1^`4w)-dT?^tX^eK%*PqwqRqW|>Po-N^o|`3s^5m8m@tdm`Z5a)f{SG
J#=r+0&P!vbB%TrQ;sEl31?Ggrzqa-TEV-LNUZ0BWGl*YH6C|Q!T0={%!!Bp*)qo**UvCLdv`!XN
L;ca2s+i)ml;x8=cB#Y6#J!3<#9+xY`O~~-4-VRm0k!z)p%~d5{<@au-$)?i=<`d!t1qyS7t|Iav
WOeOBDn5r<s%}594IcBo*3YBu&I2tu{o3Ht8fnPm2~R&>5vfD-Yu3b`mSRdwXp;k|%yQ;{d(u@ft
j)zX>1};2Z6e-;_R*;?{s|3kLlDn>^iM&4<X9au#<wv!dfP!BzcFdNgJh5SoGK?CCYZQH;(LMx&A
C6!(M8T_;~AG5)ZmZ-M&ImZi8)>x`aq@>pVf)n<x)9MTp&GvE`h_%+e^Cu+R)T{%?>R`^c?vL=2$
Ds@=StZPr$d&xVVdSTgN3AN6pE~u}Zj&V0GWhg`i2h?<Dl@E2uw*N#&b`9L>CGBqqyacDY%g-LJz
(M>({4hX-H>kH^x_v3LTXD)wSZYtk#RUA5tuCkZjpd7@5{25mfl-lWT=9_qC_wL}I%vw&j+PCz(f
;2oYc*{WXGh^G$@ANr|a%wGlNULkbq)(nj{Kfng2-Xl5@74;K9=pnh30Qdh}W@4{tG^!m64Yy$>8
%*vddd@pAjUm(>RdE!aT38x9)SreXL2y#6D(2w_p7)^foTuS8ZNiwtlM&nJQAuEn9Erf)em1k{F%
u=p#bfRcnMk)9zc}Lp?mMQDii+5~bFnPYAfWGJsd*9yRsk9FJ?NG+=ClH1X)y(+iZGaDybd>4USR
`3+!gcONW~5!XiV|ktSechMVB)vr)9j8GbyKK<ZPlo)XO+b92Ql*p)UrL?J{2UUPWmsp>G`9u>A7
1Q5Lfzn>u8&??TCBwXk@6p2B0;r!~1Ja8u~QG<Uz=$j_4{{Kw?SvZKM5n(yN<xJ3aVtqB7rxgRy#
+F@Xs=LQs-$cc5|uNrF0$_T4E^cyW^NL6s;bVUaDdR;M^T9ql)izlhPEmx()N;J;Lx+~&1N}4MN?
X-+m+?mL;ZbJcjm;o@GBT@u!CuyuUG#v^KvSBPFe#u;h``T=h`2A<hz}4Wn`^vy@+5o-dotUlBx+
N^-#{VIRu5k72Uq#k($8a9>dUU?U3zrr~Be2@lW1=!!Xk8xBTMy{n168hl8!ea9mTBx-mQ@J3rQb
l_XjC|g2+~{{P2h+Hdrxb>sg?UEFn7_8qLgfI@8XKa7?W+TVnU?ZlS-nG*?u$laMMdf^LodCK8RK
%uJyLSuYvG=DTZxdf<1`v*7Kv849k8iq`1PHz|+kn91{am;Zy2(8~2t1@z})W_*KtSyu%m6+1BOA
cI-*Ve8q5J@Ft@=_*K~FNiY+dg(m*P<(sVms{=-Hp`0-=8*J4!wWOkZj5MYtZvc*&e)`p5rhrgD^
^Gd{wcp#NH(7x+x0E&#uFT2bE6NkesiF4G4I4r4WzRAdEFCk(U}_7?Z1O>t1-#;BBMt2X9wjxpGc
u@beOdFIGtJh#(5$BgbXRcE%Aic^eX_o=HYz=2Th5paA{FFi*pfpXNJ8?)T8(ayO6YObzsB2YxJ0
f2prW-b@M11nsd%xvwFM|ZY}hnpIRC~BKg0^#9xybqunm|=MDfto#sOu(xSD55DD$c&la{DhOI*A
_m^tl~rk=;Bf(P;H6a<=zeZ{X`^>IyORcjD2My_SXZ7_(VyM!R98iR3E>^7E$3PTEwmHv}V+Bs$5
y?1u}TG4zg;qThyl%G^058iD;VgEKxAMzUFg$)kZcnaKCi1-@kt%mz=7<)CEV#<(oX3T&rhhsH1n
Lqe{YV@cNQ!{9b&sMK!GjUZt_jIy8-9s&gt;$s)H|3VHQvyXV+~A1ol3DC`{W|ri#C|$|2-=#+s%
R|r2b`)`f6&z)RI*BCl~t!|2a$RM?}LyRHoI<MHn{^9NZdVQi{xv%PKXK79gXoC4HEz&XQZDiQ??
Y3YMxaGt<QAD?P<*^y{UsDVC>OO5p~nVG_6&WdS7asu7r4v_25qT8{9DtuHXHi9^K#e8(psfbf5c
wXyq(rbuEqP`~NMFxcB#RFx@`3nxXCJvZNkTuSQIWBp@;fiDv4E->GQj@TSYpFQxAXyNnD}kTYbs
+1H}Q_uIJ_yb(bmvE^lg84=5l$&dg1_JuG~8q@7_a@3GM9x8MId8lxtGrIIov9`0qzPqMJAt-tyJ
Fwsl)&PSxF##xDHd-ntL`Xrw75fk*hBGIY_`&3?bFBpcg8n8=((hqlUz5RDve8#Of;<dA>4=bagU
kT(_z|VTbucaB4MUDyuPSQG3e#JS9Aoo}CQJF)T-kaBwGoqstz;%HR1ip(Wb{dG<1SyAFF9#^ZM|
hP9G{HNTXX|13p85Y^aw32l+E(H47^*;E@IwSoQ)NS?p1)uL!+RKhLg`@lgY+X6|HZ0inbODE@gd
t7Nud6hw-c&QvD4^m#ZJtTW~4_wOZ_>J!s3a^Ot7BR9)*Q4Nlb`_bgj48h8=uGfvP5^|7InE#J7x
R3hUfoyjK4WvBqx+)#f}p(V|SZEKf3Ga9bD9clL3*or$=!nbje&Qev&kS!mZjkYU-X`NxxXzzLLf
~t8}gupH9e_Iv%Ou5f;*+Lk4RUz`PRYh)PWf^6Zxvc@gssgBkZioJV3l^X59*?HYjK-%8SiD6JuQ
cYO%a$d<I3N}8x|XOq;%!@pT}v&S-JyTQL+?|`N1g7{*SaDsi7B5(`>$;s#Z+z8i!OVatx=p&Qgy
xFt=<oXgf}J5kegxu_~eh&gla8e>K9yPh`)6yH7vBuwI48Q0kNP^v^$}oFvt}1hTZkW>1f*#vsEE
f23Ok)cyi}3;A{0MyOzQfJFCj#hT0_a>`f<k(ZVl-f$kZ1is9I|C%~zibhPR1L{ztvI+migLai@i
#c4ycQMp%lD!4*gukY{NSzS(;(m}6$=_Cf-47-CPirUFen|ti-UVS@9gVQf-r(fUB>7du&r=bR!a
_jDu!EOO3jX*h;Nd|<IG3vX{Y7eJcMnczlZtxvVcK5RVvTThTQ^~)y&vc~*R?s~_ts1*npFii&G*
9p5(U$yKS^oLfy-BxGLUwQ6p#f2pb~{nF8hlnBDm&-{vztSg^`wZKMvHq88PlTDY~ifJwY{@!v)#
THn$V!0{kAH_bY8M_RttX>HMco-K;LZbtgilGCu>tVo9I0HBaDq4h_p9j4AGFYZ5Nz+Oi;^PDOm+
ZkGEr~F>ZfPs6&hTR!tKlOz0I;a!zZBo<BD&Ky|>3)4dKz9+9@)$pfXi4zmHW@!meCZ`Ny7OnhDS
sQ2GEy8d3H>u(ud|IZ%X)`QKyLZTNDeWg#>Xi(ns8RDzaj^UxGX5Ag(S|Dooo1Ckg++S!|IFeF{@
UO{GcEjRukK%ex3%ow#h)&#4TO9gi9reFtf>y)ZHn|j*zNm3RNgmxE0>YM|@D#tO?~)zcYqz=P_w
GK$aoa4uXrC;$5j%AbSjVYNH=moT(k~VDIOAOwu;EiFQ}H%r1LLUgn}m7c=w+))Dpw(6j(d*-RD$
SvrI+1@XI%sQ?T;Lw3?<pxB-~)!FE&l=JTyP*Y0K*EFMyex%*QWU<Gp7fb>+KekY`hIW~t-bO?ob
C%+Ex$579#g?c?rp%uj#Z!AIBdvWTc7J%J(2X0%^@!tmX!s|lw4OMl#h(Jg_$gYqzJqCH{rufXLC
V6s0vq8+f<gHK>E(dgRNcKiPX;I?`F8gkWs)VEH0vuo~@__wGL{uH$t+gkTMeCj5&U3PaA+N$t2J
*q+m8rfsvYO{A(ISkl!>tNQ1|9?#RW9o9AHKIN-1ZSeX9ad=L#e&akbu?e1w~|K`UKI;ufWXGHsY
xG%wQHhcRZyT^F}?vay4BuS87})osI$~`Y!DO_Hm?DGgW|TH{Os1%HZ=EF(L3JSo^eyPu5LA!>au
FBbV^XbcMZS#VcJS=EjT%5VcRsTjOG+}gCoi0b-`*%tNd_qn;Yc$b~%9IKZa_f`arT_f(rLr@+Ga
=e6#vJIbCJ!6<`^AD}<!9b=OR_TAt6N8O&FXtm&#FG$>~~YdCziMQFtkg#_pI#p#wED(ATUEZVM(
3nn=p#5D?V`mN?LzyNMXBj419w?t0Tr5OXgW+H7l%4cV~vu7IaTkpf*eJNF?ttN}k{PNjzL`2dvs
3(s_^U^s;sHQ}xVcaQFIq#z{og%H{QNs-;y+FrJ4hk|XfU!09a#*t}*X<;`3Labwj_AhoY(Xh!Lh
x=VooNQjsphdD)pFU}aFC2D)y8s?NsXtg^5&_$Egg^A^sc6^>3Y#jy$mu`-3fJP%h}luVQu@31G8
E4;=x|6x;GUXe6eaYFI7&0O46ZFq$)+!LG}K$?Y*V4b1SDZ_H@cU9h0h@!&!IT>%xC_)<$-_b6pe
jf$$u^M!HGji)9dHd5iLF&}CvLhd0{9Wedj0-MJ>IETkt`q(u<RxO7Cp$qw0~PAMK6759}N9k~iZ
ap^ROc`k8#8?z;gD09#r1xssjAHJEFrgSIs%cwtk-ge)PkKW@mHH?ns6Kd6Va*S?WIghUiS(jAY^
*c3|4}H509l>9PXR8b>hoH&|7`KCTN^Y^ld}tJQ>><@FBL}Y_ZCz$+0JMF($#jl1oJ~zPNm-KLax
Azkx*KyGP9q}Rhv=@%v}LE(NmT~!AA&d)FE2#?DU8D+<$Mj_y%#~Y;2>}xR!Oc>8@_;^DUsK&zfR
=Gb{oA;?>Mb+yS>~Lb7;gI4m`yGeZT(dcQ~XR2E~B_Myxm-NQ%*j)M#Y>w0s^dWpK6L-`W$5c@I5
D%Wm)2UvColAQ?3*aQIXeAk6ypS9Zy7FT)Ij6w-XedrBD2DHbUSoD9jcxJf8a1tpUF^;ZovY=zTf
ECS@FH$vu%YjfZ`OcDJpr6vutI~ksx^SYPmTW`^iHY!xAb{aJ$@kr<~1`@>`f=PYml<XqSK5+y%3
RX;!?m7f+d@4G(lQq3XSbfb7(VdSAj0V3hI7}w3o60~$X|94C(^ZOptU%7kNP6N;!~xQm!0n=!@g
n3XftYX-6V>UN$fbboSEh}>53_;H#*w4X^K8SBOF1qe#bTya4L*elH*4j3|2l`YgGwrJDF#-M=|2
$d!$bzaBjOIs4O-BsP*ljxM-%)p5AM`Sqp@+)jDzhq_gC(Sb{o+UMY|j`nN8;rX6}_6fkAG1MGxC
;;4p3u;1^+&EHJ_sxPs8wT{xq!N!o^GQXgS;_#>XunBHw<#_x+36uyw6%c?IRY|ix;3}_%f=9}E8
GFfhJ5`r(5$MD3tkgtBCtYn;p@mgUWg-u)ma54_NNV{#7U=Sk^F1q}Yvoj;^hQjN1x`*APQ?VdFc
no>|6^7vtM6YvtC@|^N-HIIPY4uN36R^-RN64it&KRp376h-obYba!IDh?a{Nvlp>#Onmix1;Bc*
zZoXkF+{JQ0T-=#fYMce;%;A<_WkKg}3HTeuMwEuu}2knM;cG0>#S!*&Z}AcuI|Y0&Gdi|^ijcr$
+S?(GG|-BYJJkrS~D<NGM*Alm#SUq(q-dC)VTBq8bm%I|Z^oY=Bkj>R+%?xSgJH5QB25-1bkk^K}
#A66dX-m0{l)wY|}wwu+po7J})BYC`=+as6;KmweBQp!DdOqIG>rEXT%HBNTQg{RJ7%!x-=vGWdo
9I6i;N`pqZ_%N*UW6>Lo@MPx)bgx;KWXVY7iqeUmeltQrTWRztvrBZRqv+E%H@{ID$^n<U3uiSM4
WPzkjb%_=!YUuRAN5rwcEA>8;Axsp$zMx-FFoXlc9a~@3`EAMB?u@~&JHQ{AVU)qgyck91Ra_if5
dt5Cz)E4vNO`)Tooe2ZHUbd`-9QQ>YCyYID!E`ry!b^N|ncbCS)Q=22^cd5{jeh)my8B-u4a{^bH
-*%P;DnB80ld)J1>lqC{#q?l7GX9#lG_qYN87gcTX7SjehOS(C!jj`L}ll%Y3)+;`Gt-g#KCu^ZC
?q}c}VU=?td=iVxpUZG_=HMzMc?)w;z3Yo`<6H$?VJGT<)^0{<Q6*y%rM)VG+6k#yXd>blEn4bYD
Kf@E6##$%eP+~01O}aa`lLVvMwseBvtdWcE#L)!kS`_9Tlo;eZ;wbra#`!q#9+%G5Cxe|2%n&j7q
{EY;L~?W--^#41W$1WSL=GaD&8*y*Sb<Bh0)qUI&8F?^zE;uNgz{AtRdj2u4>3bVI~}r0B%BA+EV
#2_geB!eSr;8%FPW$gc|tk-4uaG(x-(>If`!T=P%WZTMq{ZG`H1xx!{HMYs3w-(sHLd^=Po#QlvM
`s^uwF;>mNT{R5rUDic!lNqDub#=On4t%yO>gta)ALK+7B`_BOkq{UuK)PKOjFHnU8+gED_YRf|B
|t2yOLV*-QyvaKNnBL#%r3Jyxru5xPI_pzNs?MpHxnAsyJYXa?mE~XU`tHj-;Wu*Rc>>T-DpNvB*
;t4OnnVls-=31dlM!y-EtS}#fQ`AjpBO%Np85g0Y&Si51{z@{P>aL~ma?L9YO~84ujDu+iJv_mAL
D4*1IuZ4qmBv=9(X23AtxD*^lWS4`sx8KcM|go1qwSYV!?M*pxDSOAeNEX(#pA~gd`?%eZB=xJK8
Z<GuOulf<WL$P6JaMPB7`!>r#?3n!QnEL84dINAfPe)BPCc)WRoD)rsFvbYm9;8Ly)VMGUpm94st
0BV=6M$nvv%XCGlV#(k<kTzGoY71CrN-Wq-)hf>a)hPUT$3<QY5?4^LT~+!^ngGCR>P2qT#2Ly*m
kXKE*8oNsn$64e?a>w?EUtK{**ARU#dY&i$(j>dTqja2*1#nlhMfteV^lLjjID3_UcE!^2BBN?-@
ygdj-VRegKXS2XX;u+)fh!O^?Y!*0Xo}A2B1_Tekm+5*W9&(`)5wWu|KlJzy=kzqRjzj|JRh7{xv
&YGd7itjCEoWVYAPh~|+IVD-LB92L!t+-bR~N4@US3!7WjiZV8HuE2dX;43xPu(CkI6jTN8!Vm(h
zF40f%yrn~%E~c1Mj9pd~U|F7axwJ~TE0*EOql$j>_o->N3T#(Yk*ti06gi)G67wWxu~@hA>+JP$
$OEgbII)U=`|40D#TN+svR&`MwSZK)ST7V$F{COwLdU2sV)-6BP5f94i8KoQJ}_%avmHNX7~Z#&{
DEom2$GH9LK^VTh~!O#w({akpTDR9GvbMpch3<5h|F-#5p5L>*9G{r={tX_%JRArqs*%1?$faA-e
^%!Kcc*fb4YhQIPG1*a6Y;@oknKRq0P_l4~K;~s0dbpFrHDF8!=1_iFn_o7(&G~`a0-6Sl?0p(IX
^I#v6rp-xr&2T}5=@7EPJPJ$#-;-!F%e@1`B$#Dm&dU0)VNIcf(w8uDhtKLH=<5)=8GrP0T*hCUf
5QC7>j5&UXyn+4j5zbQs-vJk9lx)@37&1r&~6)DVyqTX{xuQsd6z|B_KXWOV3)Dma1zkhF((~h=g
bt{o`q(J^+Xy*AntwPrcie?;0%Q<@%_l&{YhS?5vi6hT2U^@<NzTyC`_aJnHmr&22-9P>&b%QRnc
sa;_N|&bgrXS@V`0ng8dBFl|zkvQwNC+u&@1W8e-iu;iW+-&|`b>14GEmdFWeL2({Y?Bmj^nu2Jk
CAz5AQ8D*>i5=9OQIknFX@PB-5Fd4v@NVjND?z8YpP{ZWqFe;{ZBBP}Q-CL>_VfG}H;d!9p4(!RY
H~n%l*KH%r92SG@L~HiZAKVi+99b(nOMnU_n+#YJqI0%g_|soJK6<m(LuUEz5X=h&A~}F<-#gGZJ
hF5Lrm4#X8kvB4ZdHM{{uCKSg50)tl&VLnM{u?_zX$c->N(k_byxaJEngqE5Ia$?RL5?BF#Pg;MA
I>g-7E+Ql$HI;Gydf3Ijpo>3t*n@ypH?yl~IhT!C6h6x(m(6=nv>&-%`;k#H3cw8_y77u*F=k{6b
NFcrYo#IaQWfJmnJBs36e*5CzV5RA7lTElc@xjLxP%om4kwBOEDi<o=Lwg<zaNZOdEY##-*&4oe%
q-_)lX;$ud47bFXg681@W5J;PZWc`oBf)hdt%+Iskh59u4p_Ln%v#RF&gB-#R!I$0VGxQ2vLrjBx
J_pwhGBcEkbH+G>Lrnygn~(#q?b>YF&F71;e&@|&WMw@G=$WF&Z)bLv2hQ)Qn^*~H2TCdb0wvmNu
AsOxANdK!Y@t9hzFuBiA|nOEad69&rX)|igPZiIkzh0TtT(NiY?zwgZwGnoW;RnG7HG}WkA2-nD&
Q*az~8JG&+|gh69EYX&}2@dW+cz!T{rLF^!z1u(bmmyTX@zwOAms17`M&Y&z;SvWGl_9$6KUL?|#
2mvjUtJmwytxt4FVE|>sp4AgYF;ZBs(jr@knSniyJ$X=&w(|R6FrLaTi83#!>J)$i1L%I5F?$HfA
;Q^t@`{CmK>+_cvhC{E3WXmAqTia@{H1g?Oavbq`7&UBeo!%qPDb6T`(=Q_bBCApP*w{}X8L2UVt
d9DCGgF1@v?ry$%E+1RB6fxK1;}^J*h<WqAFEsy%GR`Z{Xdmy0=7wdp2-6tT$5tzBkYWZW5Lu{F^
Q8tFH(V2dT}7qEYR4^d9TT?ou+XoT-#ifB6=lfu#2@Asbi1CncsB10kaKqwTW@q)s$r0V#*~3W4J
l^_N%YH5<gs=zq<G!;3I2gPW#<1f1=kvU3|E@eD}6||I~Q-_T8(CD}H5Ya|!)hdMIJC0$ClI@tQ$
ddFK@R6PTm{nWo8aI!xphHz|vg^|)==0OuUw%VD<+>VOQySrvZhS_^co2(u(gEu{y6OzB!li~uBl
)H%7`{);i(3EQO>(9i=*b=VlTRZ9Ya={`!w^milwes(B0P6Z3m-;MnHS^j;{ieOst$K{g4F24A1d
H&j7x&=->3gWTGQoPjMQI93}&UdHvQwBd>xuEZlW^8G|wQF*1HgJUQVOu!j5IY_b7R&t+(&}N^SE
-k@*XLWMTC``>2o6B;>&ur0B7X_XK!<<^*>CifQFp-a%56?xUB<%VXMR_z>VJQ8Mdm_gz7n7@lID
<P2Ae;_^OQ#@_1)w^qfNbft10h=FFPm_q-QZ90T+P1akxJ8{F24tBKxvTqkombQZx8B;Z=AoW2?$
h>GI~l<)rLW+N~<*6@9j@Sn)}2a&ex=tNS38IR+jK`3?OZZNCz0p@kfm<bGkN8SUVEqYJ;at=TN3
xwC7*aL^xB3|(qI4o725bI8IOPY8IzksFB;&uLX2bHel++R`>ElKRwBXmZ#anPxB9SeFluE|5a`q
{mNsKC;<mb)&6b4euvg1JO{nQepHQs?ps=(PtLbuOse+s~x2*LxRj7KDQKdt@Wpk{^SyM_w?)PBd
@FF8kv%9N6ntD+1pW5K})l$3TX0yxlp9%uTlASR`+ZJP|ANhNjSc7P-I16(8+8-S2nDT3C-E1-BZ
|JiPb#<7X^qmwA<O3Bd+lZau>hTrT>KbU~uS_^WqxL&bQycuHk%^X}q~(lY0d^@?CCO?9-)|f#v%
SJ_N>oMrN-{o^`5%+wE|-EgA*{l2H<7Rw6K?m3B3@W_43A+Rv)&I(zzHOGEzM9gWm+#>e}97uYLy
txCf@i~ru%$wkiY!D1K;_5yL>;_WM5eZR?X;=%Eo2=ZwZ(KEcLfR<p%0XF$k@PiI{mSggIbVO#ph
6aRceEHN;a<k2vY_rm?+QJot!yZkw`&wvs{6`U*n@;aPp((Xlv<!$68{W><9(E}uU(VUhG4~u#8G
bpGj-sPFFB$eIM-5kkq?kSMfqS|o|NpxCNqsGgmHvM6QFJ#hz12(?K6fO(@|u;J_A}S#%4o`-lPX
b}3oP|Kjc4d>Uy9$j&<%Z8XT<HWaq>~dxNM8*nrkd&^g3a#3<!>1_l=-Hx7JZPJ1kq7Rpmwq`>G9
;FO%s)K>h-n%~oClSg9Nk>rT%q?q21nq*Ket20J~i!5@t;1luZT54D0P?_l1_8O+D%jQn|lhanH2
ar&ur17!i=+P;NBygxekwDoNav_I>M9ij40E0Ap5<rtr3pxO!qM#l%pu$~Y7fhK9n*9VjX5E_XC(
nvq>Efl&dBJz2<0$zKf<Oq6rW;jEX-dn6MLBLl)7EH)l%d=dtBI(M_-r*z#!(XcidpgTPeh006nP
;DgfVMCsb||NQ+-%}JV9y+*!;%}>UWr?pZ7R#HFV9qb{xm*%_!^EtYv`n1lrM%n<xz=}?4Dlh3fB
xw?SSDrR#o9$14|kZKUd>1z?qLFxOl33hX~i2i~-6?FIO`%HN(=6f?cto2)R*^1s^>r$V3t(8{RZ
|kuI0`0fw1A0MB-GEEd|~f!kZiOHXK-<y%VV)j-$?B!RwR^ugS|+ay+a&m;-)bTi$F<5;=_1Z&Um
MA+1L6*(emjVn^)=>}(1u!@T_;30j-_z6R!AtOPNP^Qapa%9g42ret8s5`=o64F2F^x+h2k?RXlA
8YQE0tcP<aQR!RZ8ylR#vl3Nv582uu)UGx?;|~T>fEPFa>m$23L5IZ#<h|f+R3!qUOZf>MOT>2gc
fMaQ|}zRQn|4z&XHWB+<($0Ag355vfjX*z3FJh{_Cm*x>h!>bL*{Adf)(QkBsH$<drnP;#imm_u)
9m$H?xWXJP4HSaxS|d{|+o=#W*WN>;W^HphKXP9tB&5o)-r>|%{4ZI!I}zC|I>!BB&QZ*@4hVCdu
BrETUXcf$Np-l5(AGB`ii&$eVq=q8JMc>F<UzIxQD3C*B+sO`n}b?38<FYYWPfcY{3%-5@rGD4WP
4_pak3a&LvgjZa6UI;3_S_NA&-i*m5W-OZpAb$7a=ke9c^Vb;S@^#I1EiJ(D9hl!tOH@lcss8TQ(
N84~*~7J*3A!v|M3~+Z5qvym-`6p1!SPt%Sil==z_1k_OCork`}hAB!B>6q
