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
rem  It needs Python 3.8 or newer and nothing else: the extractor and both
rem  reader modules travel inside this file, so there is nothing to put
rem  beside it.
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
"""Unpack the code carried in the .bat and run the extractor.

Written out of the .bat by its batch header, then run by the same header. The
payload is everything after the last ###PAYLOAD### marker: base85 of a zlib
stream holding the extractor. The two reader modules are picked up from beside
the .bat and kept in the same folder as the extractor.
"""

import base64
import json
import os
import shutil
import sys
import zlib

MARKER = "###PAYLOAD###"
READERS = ("avatar_mesh.py", "lzx.py")


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


def main():
    bat, cache = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
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
    status = ensure_readers(cache, os.path.dirname(os.path.abspath(bat)))
    if status:
        return status
    target = os.path.join(cache, "extract_items.py")
    with open(target, "r", encoding="utf-8") as handle:
        code = compile(handle.read(), target, "exec")
    sys.path.insert(0, cache)
    sys.argv = [target] + rest
    exec(code, {"__name__": "__main__", "__file__": target})


if __name__ == "__main__":
    sys.exit(main() or 0)
###PAYLOAD###
c-rlK3wzr(w%}jExSN)&B}I}S@n~Z2I*Hryy-m_DaXanEz8YGhEG87G5h>eBr}ww-c>o{)f|Anq-
f#EYO`KRF@jN&<IB)#27u`o?v>eUjV%Ax#_Xc}k{ORecSU$Z?vZrx&FBa=^mS+do+4Ua&eHD-MNi
4XQn8W9^5c#SU`Ba?K!}Fqu%kQJ{$4;4#MUs`dc>ChtI?zCNHA@NsKjkbI^Q0(}>`tUf_EAjpB|S
WNCGL~>VL)FN(1s|=d>I!aj>a<)VaxEph_17r#nrd(p1!|&_d<;Gtc;Q@UW$iVUc}-x4ocjnIaCj
li8u(c&q$1CPzuNS-QRy|kMsEg8ZP3=bw))CG0W2ljwlkhN!iBU<B1@+h&OpT!&kF-8AE@obRuqJ
akrud#PzD*?H!7wgn6WC{y-DF&R|mWs1(V3k;d~lE1~4=S^`O&ua=Pr#>=RTi>D0DHdiQG&{7enQ
y9o1Um|3$v&T3~qOS_^F<xeI`t&iH%SuJq5)Vl^BZ$Go#Do@T34j;rr$<;)g1mq~awUbm;-XDc70
*4ZcLpyR=&z$RevwbGbbk9m%;9SXK48-?^K6<d=P<kI4gg$~G?ZeNEEez#+a4GLgW2J0S~zo|7BC
fj8D+2_y0>)_r;|eTdI!(MeY`A_G2p^e(eEE0igKAm*<A_`f^Xuvs?qBo^s&U@(P2n4|2{90GRd<
7)@>dWssd<UT)ufF3K(465?Rhj1-J&i<1$Z^yVWutRI{GPQ2|ei>#Wy#_Gb~LIh1-7!D<2E?{$uP
^3l2_x*ZrRfBQt!5x3DtY!uMrF1d%{=2;Bbla+w_^V{nTPyo;hpb}+>deB`*Tmgs}F5_sqOrX*tU
bYbe@guy5q16P2iqOCw9^&L~hKN(-*BOFW!zu!NUE~F$9<9sAIE~9Z69Fv&cXAX8K-9@HdJttYk2
?afV1Ap@Zn(}gT;#6D@y39xvB=^WmPfa_4<C~(gQ9?xvjny*Y&-<7u?Ma*to;|-@{t@Hkr7emlL!
D9KN8kYm-*b<EE1G4LaL;t{o67r%QzGFQM#(;DpwneD-_Yd%CmHhyBYRb$`#V6L`Yp{a=&A>AAaO
_vj{ffG|gd8BK+Yw6ko?n7(7%16psih41_FB5H1}>C~<%=ZJbK9yd(714?Yxm^)@f`$D&-W#%1+&
T^OyvZpLr#FTZ_re)Yq<i_!bbzh8(`(S7V4cCWJ+-@SeL@1wt7oWHtwr(X5?03^Wlw|}b&pLDxjY
=_IgIe&fe9-jZgB%(VI*L#;405q9g@3r`04<DYxFd~Gke%!~$SMg&B8$&-lz=yQ2^`k?4^nMmC;<
td7%LHhEes@IgB>L#5$J8Oxo!4<0O#lUc$e?Ngy~owCo?)q%D>xwLFY`2CUPZ7m^xKnK8$Vht{E9
HR&c-RwH{9n)d*exP@i>kbIL&Y%i6*?~qF(^*`+a}#T){Ptqj}Z$i==!{k7S38J>R{5(FUpt#1!k
mYb5D800H)KNpzA=QMn`K$pJKW3I`#Onofm;*eE;~qfwG2<!BV(+0qgS5;aNugHJp75U>G%IdAgm
6wd*`Am>Gqe2Paf$O7I0VG5{S@wGTH`yS8Y@kiNlwwhCUv-4zX^|G%Ei8H4cqZ0mEMhTwydi}2V5
MBtV<tjs>_GBW0efSTK{U?*~dQUtNfzeepoR-s37@8Bn71%s}W5maYTStlQ!MQzAgdff`tbDx}I^
bo<={~Esa2l;rcR^;!)On=W&6srcHjSygYQA~_)Emeqy*>k~U{42%0xpdZ6QQ!~;R&v|S*k=@eF}
VD7MzH-S*b-0hj#IKRD6WuK~Fq?PIW`5)U(SFp;vQ3L>tP^&(6fb4gPQR;w%A!>tE0V_4Fk-7GiG
%HoG`Oa{rV@V!tAww0&<B_PXyZ)b>Gp83Pf`<QQGF8?8>LxI#Y{?_hyWw&L6BM7St-QpY$s4jM0E
d=}P6(>tb-n8T>m>m7S49`v_YJm}XeCZ3A-3Ja=QPMi0DK8#H876Ek+Yc3!3LIGk6uu1j4jt?7wZ
TFdl&N3k9Q1uaHh`wRytjs-P4i(7iBd(2Rx&dUwDs)!Fx4;5FpTe=Go~mb;^vncP7!JEPW<Sy7KF
Y?iZ@wn|37fImYAsFfvQe3jGT;kn7uLpapC*A#_Me3S!2f*a9YZ(#!_MI%2F5T2O1~_sgZRgI46^
2X{mMR%nN4i}a}{MJyq#ciV0Lb!0+~*ba$6uAK1O$W7NxKZ@uEd6d-Mn#Fdj*;@yc1T{a9x9pawA
NceDhCbA<;jm+ELFahC^&HG15&;Ck1BpLQt-lK}}CM(g&k=-6>{mG$RW`Lt^l;7QAf2UUaU*P`F)
ddsgH$_G#Z<jjLk7nz;l7`}b|H3)x4{%$`tHFIEA^zs{ZjQE1&Ln*lk0s{*ytE_<i7f%LS4&nnCc
Gf?kGek@H^^p_?W^?~Uk+|FG^#6m<wB757_s~!qHgU|7-#_6*j6sGGF|bx^(u#;ci^t<=9-Hl<kW
GRz9ydf7qhdXu#~_cPMhM0c5l6P)?slH_df{J0zKFB7RD-0+?N^1_+$0|tPrrHl?)CZA`_6m<KtD
iP9r$44f$@-Ar7R#K1Ez;{3y_&8or2LEDk5-FP#JbFaMB8H0QSW)pRC5*@*HH*Xk4bKLQ&Nnqz+u
14>d1qZUj1Q3<O(mZe{IjWnF9K)8<w_`C9o@YXugo!g5Iu_U$e3wOHHbKUw8J+2ub$`A^p2xCW};
b525TW*<2|b0?YY*nK`)eLmWKK0?(;tIvQs4aJ|Jhfnm;Gk`}N0PH=x<Hy=*8&KgE!-{`>3QY;}M
`R`&&W;y&MlkETNLQ$6nkJ9&q)mIR!aeGH*8`#@q|8EfPrr#^QEP{W#Zr^_V6)Ux;Gy16Wm6uq?_
ilDhfpz|%EodE6}jk6LK4HQI;{B+711rocTk^L*BwbF0oS)(sL9Y7ox4TuHK#)G*yrYuSJ7~;PgD
ZdVGDHy+LItK-<7i<Y~~fKh1@rn&SV+?5SB>k!%@Qne-WTaC;4GuDhn7xUn*sKuir*KuRS9j1xy%
qy{u6mh@eul^R59-k3XQC9ctC|IZh}_QZY_*<OEqESd{sqAd=3idjw?~N2o)EJrqBP5^#o;l%y0P
#UQswvJUEWGtvbV#If-R|3bwC^_HOSlJ(R@&Q=N8agwG=VcjvO&7a4!RrV42u;C3qzz!<8+trn@F
s+%~x~A^Ap*k^;0D<QL8>4Z>{f|&pO6>k6G5pv}OLiC5Gyy>HY6Gy47kh>MS?O}xvZ{lgDD>o|go
X3Yzn?2)&`STJ6u@CvLMUk%U;&LS#eH-lSgC9h1PyQrO{&Cjnn#ZTe$=G_{JOXgG}yFU#1*a}B38
6qM(e<+;;t{MvYXZl(6$DlomPTsp-%17W5?NvQtL6$7=>?ds!m(NQ2K_}DLRxR9Ms`)1D#Q)o8cl
U5A8TS7XLV@3=I;B_5gz4j+lxBx2x$iUfSg6g4j?hFaTmuqV5-|QIG(kiL-LKW`0L~q1D43o=MZ<
I?ba=C65u#K%cne)Ez%ccqGHYAwUOSUGM#T_3gXsJzE8XTLp`S;<>QZ^IMO&Vuq@HZq!6y9t!pCw
0NUOW_H^@6o7<!tbd}h5<tzd*83;hm$1#K#<@C+iV?~5XuDAZ;`Sx(r%73+@d(9)C{rbl%o54Opj
x-Xe&3*(_L~Fwrq*Ns_y#9zkA@EEo`!}|>D1C#dQ`+je5wk7H^5!w4nINf1J)AO^)LJawolazp5d
sz2<%51mUR568FT9jHv0xNjL$B;;YtVH24M7+%$qM!%XbQUg_q}gkMPA>Dyo6%@;in9*r++i-N49
InBdj{$y8Jwlg>eC_9l-&!e?`LO-5*yJVif(4xV!(COm`|E*X^2L`sMNF!mEtO$GVpmZ~OdZJMj%
X}=;e^$r}xvadU{bzj$gluz95t9HF7nE~ADb(xn@Dh)i`_}9kRt8$V)s{Q8znwq(((Lh;?WG*VQ-
B?2?#A=3u*#Vmj8Aq2s{uw7))g(+J-%?`_y-?vDq-%!OnFgKwVTTzplIk==Lo#Yb$(9_L#v?v|E-
x-F#Iqx`0cFv0-8&ZTGd4W8v};W7xQ%+mAAZEv?qlcZf?2_0wNaFY#UMM>m(tiP38m6+p?N)H+8V
IE>P+;yAr<d^!)4~E<SYslm~>MI-+ZIVMAe2vBcyH`NAq>n3Tf9+%hm25`rCk>8=GOEUGF8?6i@=
IR>Om;JUvw?i!zNjb~B`A*stn7g<1CxS?M5$7w9no-9D0xjaJ5&Z0a8I#tQhCD{Jziyv<@Ei!*8t
#K8fHNs3$sk8ze4AjFj88KOM8SfFiqodTPJa?T=ogo$YZiRyL-BF!JfF)s=t1=(w*pHTo%?2A`FU
G-Yz6M!F&!j_mNcQc?Ms*c10J_Ha;Q8GOhC+#F__l{vc57C0!W|;~|I;;F7{yhNg3CTePy;WAdW9
c~X*gNlcTVi$4XDOXO&d4!^KSwES_K3Zp$b^j#xf7VfGMdNqNV3%UT}T!V3r^GMt{{v>FvRmkxfV
s5m!Z?q37tS5nQb~plxOe{yEhW2EohjpVOPkh$?0$p8)PpOy%bU$N)#NC6<{Q1N55d=G?$hbZ4%_
{_Ik>|#S@2ZndfQ1F!_>r40Xy0;{1#w9XUL%MQEi)!+t}oPst{7b_4swl=2Uqky>kV0{ca`653ns
m+L)7M&LRT;4N4I>I1(^I9~5@U-(F^8dM|DP&EdUeR5py=`OL10n_U}njAi*5A=kVlOEA0d`2z}@
C1MVTJ7x7^6vKN_$atn8yMN9;GT$L&nAj@`pr>jVGnZZ_f}EGBL+({H-_S00zN{`KA>xGhY$Po@D
3jy;=|jj<Smyp=nrcmMw7=fVBy}vNjM1~%Ol>or&r60U6mf2KoLan;w4N6juIpa_zk)$bJULn(9Q
#5tXKi#aw16DZJ}Ex2)^tbR|3~IvCbRml9a9Hi#6(5vW10jILJCZ&lVlrn?(?ySl&~^huO>Ttcz<
AK%g*<M<Ez7f$$Kw2uo-Z6q9njh)<p3D7OJLEcO)}fd2uD3v@;b+R$S^91dDyFlhH~jOVfuW=>9l
@?m=jV?Jx7pTjLc?G}}u0dJ#yT)wAI#UZSwBo_LS$qZLufZAVU@!JRf?U^_Fmf<$U5>%W9Wr=_=C
zJrOWNp6C8XPW2bu;)E42f^j1E9v+x)G!Eo3PSs+^$iHv5d027)ER|=k)f`c>7S(u}`POXP^lI=C
BXNLwgch<CA{m^%;_Of;1CU?53u5!j<son<6-Vq8{_#0W=3x9Hykc^lrj>73sF*FzoVwsMH^vU>l
Vf<!K{I7c-=kL+<~kUIK;Ft~i62o>5m#0CzeJf@iQG3Bo8sZY9AFJ;I@91n#7QHlXjb(9<2_=nfq
nHFb34>F6lDfkH!=VgKmJ)8{xxsRBWEGUy#U1sVpV0QUx1uEwS5ZtANG%VWPEcjfv+AzXhXr|K(U
0MghKXAQ?aqe|bda^SC$OdgxC25TK|!I}ktae=+6!)M%u;`&R^Egq$DNuE~2;nxef1T6udd;HnIL
y*{y5$(o4w3Cf0nQ9oIh`HzvKjJzsdhnZY;ec@AV}%O`j0o6mxI?R|MQZ)GwAz3>jU82;^nc&b0n
YNrEsf1C44QZtdIm^^9=8-C0uSrDK=OEqqkr@l0$CzPq?dyn28e;cB+#m5A+jR}H~y-m8N-bxJ+X
1OH4Me<X-FSn3$^$W>>l;051**Xp_U(m13ivsHw^<p<@2qcC~z3Jk9yXqdZxx*aeO#XEY5%q*_(<
dDkAhLS5jFZe}e?j689}JPT{p}7G?hB4RAFv#wcKS9r2F30>J`UojVv)C_N#1sAM5vi3g=LMsWkd
NPMQ2%(y3HyZ9qT!xZTEfX$fR4i8H}t|YtT=oVz{zk<fr@$E8)QyD%;?PrD#@hjjcutRq20NIIKZ
%31fvZoOTFWbZ>lO;J(VxYq!i49?oTgx#L2YVjR;`pP_tR=ZOCAp&Ffj<s4mwkgzjY31kS>M$8y^
65QhG$U`mF2QptLwcH%eg4nSKW2)VwB~LcK~$<ajX7yF~lN+Q?8A$WmJ+<iS<m$B{!|+{o&a!vbG
X@Zlprv@H1K=&fS2ulwYVRbsX?4d85>3E;Y=+LL-%6)d6v{!$H3?7!U>xY+n|1&wW6B2Xo<F=9us
)eqCWaOP69?NKx_-nrgMRtUqh4fA7?v>G}>~Zyw5ux)o2b?_IjSr*5G9Obe&HwPC|(;0%HOJXU~-
fPX&OguqImTViO@(NPEbx~o3ks*kS9h?IaH<N1|}OSz3o*p0=Y3fKvhTbGVxVSUgFr4Wu{u{D1%C
mlk-T}isMSZV7@M?2ukmv@_9norPQO3?!ryF{fab_=Tbq;2J39=>7(3^v<&$E6f-%_TMu$aH?+IH
XMlOKa&^THahiLT~qy1x5uz+ZAL`rE37^3`Nq4Tvks{Hrs2kiKnU;t|TKjiAgccHWDul(+x5-BSX
}yhGV%M&B*AGOuWm(eAY6W*OpNFY?{uK3eX#to1A25iMJG5-S5^)<CbVf8QX5sfPnS2Z*H)utjD!
FG`$)t7n-~%SExLVGKwBt!}-6A+2^0t66Gvk737zss1CaFWR?pjEpSV@#gHeZirkf?2*ygdAj|+p
d>>DeGGE#*oW&ei7$`*1q{Uyj(TV`TKpEkpY|W9j<fH=~0*KOdEk3NWj~&b4<lx7dI6gW$plxBHg
z;Qs0X*AonTl95PrkLaU82R4$3;9YNktPJ^nsT>L`#G2h`hQ;Gx&}CV@<)tx<8%j#<u&#F;-E%Cl
fKrW9IGWH0CE9z!>PUQQXsJX5@(ojKQ=ts9JhZp@nR(qmsPxV0p&*asme!D&bKR$Le_6<#CB&$iS
!qzG!0tnaw-m3W}QkY+rDQwmxbSayuRnuBnHFb1i!G!;gZ3x5%!*95LB4I+l|(_Hn=slYQv0Bfd8
VCVC2^$*T`U_k30HpjAtAIa!k&dPt%{*<4|7fskn=EX>_aHogaJk&T=RpFEHFP}T1p2Obd@7FC9V
Z7fDMp-p3v^hgGd93T4HP#{zC^e@+Y9}{%+!m!Lz2aUp)gdQ#sPmDJMoY77k^z|Ok3+wPFYzQZTP
w@AzyXh3FDfRj%M3AS54;=sdxl_ESV3N%<ME3Htr%08I3F3Emf=!2o5%-smqjbxei0Wmd7!W9vu<
lBvxbi$Hh&Wlq(}+=UV{Zb}b2y`LZ7gLwSqDW+9Q3shG+9232u5YE^VTv7ayb3=a*{qY7qr<4ms+
gu-6tO~Y{-2mL;0Pj-1im&WG+vQ0-@+5;Vr$N9i(9>``@8d$piDhC$~8SqyP06;v0lq<)lkG4R$@
_nRUc#&ag1yAZOHf9Gx7f{32EW2e)`|*l!&k_B9K`N)=Xhk+B@fe)<rt3lz;b8^8>?pk=H`z1yU;
MRO(QoJj41)>1mQG&?lKv=rC_>WA)@@fvvcD2-|@F5^X-u+5wDpuGF`g$Q7Kps~4sfNJ3G5peA%V
MknYly||IC@{}KZOZw0oUYJ8`>D!202F8rOa>0=LmXwrS7H(^Kcad|b9M!WLo;8NWLaDrVnM+KoU
tQ^|MFC3Qcx}BQ(BESuxl!_M<ioNOSds}WB}F^eYO!gKar2aJQ*)@)XJ!w5Cy_FlNnW_+g!Gr0h~
LIZl2LzQCNv9631Mk7uR-;XOAex#;1-2jzP;tz|<reMHo4WAlM>G0UR9nH&D*zz6Oz3LDXBuP%>U
FfJF!12P%|OXE&$tqu%jT<Wi4B@y}Hpe=>D<c6$#qSRYayGD59Hx6|u&I^9nH5WySMz7o@DTsfdD
F?Wu3W49QBt-Qef))EMI?U`l!Ijzw7#Cmccx~m3MQPswloVP?r)%!&QRlz-ICPSf9TW3U}WGhGy5
DE?qm;me1v*Ep~81|O5#GkkiddKdQ{-Ju}&QFe`>LYltIteQ+l6-Yif3=xMkoBrj)!Q`2r&U$qcH
z?C1(5aL&M%n7&<D^K(Y_W3Te$|7D>pC=+=USn<UNmj$95G$4j>M0ZAD95GGR=_G_h_6lvJElJfY
*pq7@{_yXh}AZx=<ru@r5BS_#-V%<<M=Y0i`wVD+U|jIkff@TXb<iM!;xBe#=VL=tE$B0tuONa$k
``Ozrys|MZ|;(S`h?CO}JA1H>Hwj31~`qCvVM+Pc?N99&VqN{4n_P1+Ey>G~5Q%CxIRcJCfkLUSP
MS9AI8x&yHz|7MGz5RA$$L%t<E=YQ;@@TCQZmwrT!!9db54BU5^yjJ}|G|Mv#S}OcT5t4+3@!Z#r
qdBRtInV?%txs>V>3`jJ{fjzhFWrxh93RR3QFPff0z?5B}R+JfU`xV*GGlNNTPB;ZhMQUoY@L~N<
2gy4SMpTm6YpAy;+j!1b580axlRpF2>7b!TGBw@tvjWr_=pZ<V6QN>`am+b`YrV(QSdhjUgFMJY&
q@HHk_JNYYhs;|JI*N|ZACnl*GCN>Q~JHl96J6WfL~8ch>821a4n*pZXfM70n<CPi5UdiXBiMyc;
Gc)TitU6AA*XB_8!3e>WkwolNI2;A0m=HdM&`4~WpW9gvtcrcwgTYyK47RG!m?UVe7BJT2W=%$-t
he-1N9im?{dM@4o4P@^c>9UTi5of?MV;;bO8w`I{E^l}^zF!w*JimBM$h$cgb>ImkDne2<T>QTX%
zaem;}K;Y!yJE<N=oYY8IN(6BSIBI$=wiH6J7G1Z*h(`?DpT@zkOr(_^?b$$5i$I@%R58{AD_IDt
`I3E>3C8<pw;Xq1r<S_mOG`>Y21}paEVzq62I1#=nuM#s7|dK@CWkE{%yTrF+Jys3k<F2HY2v-%y
Uw4Bo{^X5=3-0$QfasEV*q4{&ah$4REX+zc(BHqTr+ALo;$>Q~LKBha;l(yF31<VnG~&NAsGjsF<
gX<%9qGj}vOwc*NPB^9!z5!8SNAn2_R8>h2Q5yu~cTI{i0MR?B)H;3LRm;+<9S}c*n3>Gc1T8uDj
j!lQYr(Cd@uakMApWCa2cEO=+nVhDxm`Ra6T9vaL^+`WL$rhB4#>>0_(ctgx3GgDbftl|Uvxia((
qBeq`;^KFGv%k9?NbENa!%%<7MUz4oh94rF%77SW~5x89r1$mfJ&*qofMc&Ql>DWgrlgaL0$p9hd
k~%(D}MWNk1xYYY8kg3taC#+QFXEX8~Oupjzm!^T}HWD?o3ycYh!UV5}Tb`B8rRAz;Li447WTQyP
?7O7tl=S!$VFqG$LTlLafuJiH)PRtzW*5NQ#AG9f&tFGEYdGARkRt%tAMADV*JjYG#OXdCFM+o;g
gNe*X^@?JdY98atNcu%TEOc|A2O4X>e%;YG04X500i~P2s9tP<5TjIbyTAZO^{zLxZLC8!N(7-Uc
X$kWyrkbcf>fe|H=9e6_=>cX~ryfi=9(Fz1fL0K8!O*WUrz#UKnp6m*kxva=oJa7!O4|t(9%UVsd
$n`Eyjx+Y?DzC0FnI0LDywy-6I)|~BhB70%_S<Ul@Z)SCz?z~k!%`<%E^>*j?4I;t7Iwd5*X`{E}
$b%lI5)}Qt#MgG?v5VMb)`ZeSc(sk>=k3>Yckzl^h9#xJ4Y%0SWBq9p+hq^^4MQ>v%Bl^PZj&EfP
!A2s7lywzjZZP+~M<J>qG!N=qgbEis<uh(V`;{C>T+=3k#SF>`vltYBub?U8ehuNHvofNk<zc-%f
ePCH-$oP@Da2`g#LJWXV-YaO!sRUuSm*#|USkmD|OMZd7KqS6{EPRnJ;u@oipQ;{GT7R3k+yPB32
C<5#{wW69@0Ii~#Jeer252yyCC2V}68rVaX;516pk>BHo7#!qJuya!|Pjj^Sn9PzMugxqO<~}tn<
W6J|pvj{UC4qJ=9kEQ!erhL#z)}{wO`Xf6Gj)bl1q|0RLg-*&Iud-<&4H_kpeOAEAfxU6altK~!f
dF`Q#GwqB(hD&`b6jmW+MkP@#O0H_1;@_sX>(Y4cd&g4lVVgw3opm-tu``O^h@w7}*HN{(&94O}-
;k)2p9#S#2|IJ2WpjO}W~2BWSryoJbDRH?`!Cu>#&PSZsmmRaxak(Xj9=9*<({L1k&XaKKKD>O|%
U246Uf-bCuqrLUeHAf%fzoyYSEngKAq_(%<}g<o`<`#MGeCgB(vY=A1PDW>sPXrXooP;CP|72~E}
w#*r{xK5qNQB!zW<|WZWRb3v$3Fa$9R2YqzzZ{M5Tpo=yo5{!Yb+*^q1Nm$TBz6QtnHRfUK5@Ynl
&9NIxA~(uIPR)Lo7!RdAVQBa;Joivv5I?b<7<I}Jcm`kq|Ew=c;u}w+ivp-eF<gT_x*0?mX1i+oH
NQlCNEkjA99tH8=$|!)ya~QGr=n}C!RJBGDH1sOnsDi{{{0M$m?^0ZxBj5LZz}tN}U3PuCw#^FE1
~#)MB+nv0@-Sm2fBEBn&VALIrCB0ziRePV@UYUx8pRo%PccZL(}2BwH|n3Wi9QXG*ZD6VnMg*zzf
kgs>2^8N&oQ4xFG^<f|o$VrU6fDHerX&Vua4P#p!G>go)%#}^+lZb6!U0b+$%B$Rdkb}eSm#6Tf!
ufwpK<|)EhS?|?XN&uHg^K-u=p8W9s;@$V}-hOlW-Nln@`12}%$SA>&%u4So5*HuKTuM@h-ZsX>6
Ua7>JVoAS@vCKWAA7ny-d0?74=as!Ap$7oX`yA{d8!LZI4K(Q1)Z|E7Xbo8ZUT@YLH-=bL-#s+ez
!^{XC2r<a1f(G{wal4pdD1ThcCrbA-M=+TZnUkce12$_3%22(jv#O|Br>ts1`q>S3^Sg8W4ogt*$
6UyS>bFVknC^TB4yppT~@H=yF97H4$F4fSV|%%xhwj6yu!m3fcj7Ipx5b^NdFzM~E=_2PP@{N5yM
_JWVIifxb`%$sl7QofHHespHDX>qH(|1zi9`@#A{;TWnm**eJ@GRlxFcYkXCNx|jy#b$P(j#_fpr
W+u6$&^Ya7WekV?D(4E1^T2h*-g5Y1KTLV}))Y!Tz|{xFkwPAo&b=5d=}=j;w7u{;ldhdD^Xd`lv
Si;m!u}wMA_I!NATvw}SZPInD55*%b;nd)xa7aiDt$rZg%eN^&1k7gdiOWA^_=%mJ72aDjnB}(9&
rHof!u5x>q}&QHNed}S<M&r6LhJ@X}x7@jhq<BMk^?B`L0T%Pk5B`c`E`b?F>|Z@g&qWZ$H@VM4@
WY-A5!kC~g7v;dAKe>?sZR>2uuhbQ_OsDofYm^3}hPu_PlLgNz=NMV;vJq!5zBFO)EdS=97^(qs;
M{7sd(C|`((Y_xCq_)rD2yiJ5gtD-qCV2(kO_*|7^@M+*kB4N^bBUp~In=rKaJn{_@CC>IFS;|(c
U2C7s;x0EpUq6dOb(xHoaTvOqg<yR$sY|n1neuRVAshx$yr$T@mfYqoaTn*9@OW)D$n=<&YXM8ZE
=~(%LMX@(H#CqztA@3}mC1mma2PhS<&+G01!7f~NG_kZj4&;rkBsgJWOU+3H!kITrOF&uXEGJSxJ
c4o6ykf{9|xV2eLTw%Y|BX-Dwb=KDPdO^zw6GMWmTk@t;!^IufMr`^XlR!N@nJsgV^Ea)y3=4#ZO
lkZ{A<NeS=ro0C$Q9oK$&B<q0hD`+vXuegufZ*WG|1Gl@rvd84wU(PBMDUn%5Psq$S?@~3-X=aoC
J-nw=D%k|#>cz5yg=a=7IbY5J(;o>Yki68S6gEB7VtzdMK&ac<m>+_#RuP(m7`YR0Tz_QIDZU^e9
9RZS`qN}fyH%h|Vy3nhoxlS3jz&i|CMveNh#Qfi4pR0^vGSEyJu1w_tCwS6hH|-+2xDu1hg7r2rT
Y=Z!r`80$%;1rswIB`y6L0EP24(;fWh$;)9m`p`$%JQ(L1{B>$UA00B64e44M-atp{TZXdh+{>7)
e%)K0HZQSvB8SMmk_HqFgMO$buF4)aL-N#=6KCblZYIqpNL=vhR{3b%4Ae4-bLcSk3}-(myG-g`p
^^mca|7)FGU;p0jGtIb$IIOeS?TN)Lo>#U?Wn?C8QeR`W)}92{CBF}$3yrC8DBgW@F}{a1OO7R1a
hnCn%iP)Dny{{Yt$%@|iXfav@h;VD`KPCO}@kWh4!hbo?!9r2dZKmxUaL!0kD)7j+UFojk5Bewqx
Z`C_BcFO{G-3nFg*L(k2<zmB8BYmh~O#9f#(dYDwuS3s!rU5xyH7lWOZ+lrOaqUo2OMctSYME~Db
I0S<bVqliJlQ_RF(+ipm&sj%;uvNe0<`>3!N3M4l1}x>5;(NUO1hjE((xFXrh@K}<mMtg^)bg?lp
>e3CR{-#K>D^bW>i6Cr17a7;Y;+NFCP-cKNoSFIZ9*V^H2oCH8+im_`FVe@o`wwN2*du0SLim2Cj
2BNQ~JkwiUtII^cewBhuN(0d;^!T9yR@F5nmY*hdjB*#C{6B^ga<dskRWd&5-|(Dxa|S!I|?iV?G
50kgR+mbMK)0%mcL6yb}yJr+$!RtGpu1)%~K9KGR4jUEnrH>P8O%O06ZeI7+MPL#FeNDG=&;mf%!
S#_YV(p!_aHVId#U?^BP0P!4YuuOnYS=Nztw<r!%>D`d$cc2B`7ePk<ChY4hK_*WYfkcQ7>D<*fT
W>vHEphj>fIu$`xsnt<TXY_x^rLr3Sadi*|CfS}!eBy8k)8tIZ8;QGQZ*BWfjK3kDZp={JV7*r>m
1!`>T>8CCyQ|&8eH|fLe$dPsnBez&lO3}c396$RP6-~NNY3Lntv2URO|;A4|nNrl_meAd*X&3rjS
~-5sO|)AaY%2H2hEpB2)~V+>ZSIk2?GD_~&>X@_91yNw8&*cc8sDlL`6fA>qHv(MP%^*yt(EaLnY
m0+jZkp-2jlt=oVD(USa!$0)F5GOmi0ao_%M`HDk@WH)Qf(uHDgO9qK+2O9m19G%2VYD;R(jhlP0
#jgsf2cPN~vFh?zl{Q+*_1|6oc!3v!++&7}kI2~?!-3iUMGjlWd8r2e!7L(LNiit+A4<V@fUZ7SL
H<AcQ@TW$wp8zFpWblv2wKaH=n<2GIl=^;?~2G1QCHbcq~m(!P*?YiXz=-iXUMjrD-DK|MW`hvZw
XYGr?HccFQw~0v-(SE@aAhep^%~i%8!DN5&BxzGM4H5&P%*Q=D9c=_|meubeC!Z;<Rvq9E4<>cv(
<}DgM;cpZfZfo7KuMC{^pPQn^uoRuG6j3}7`!@?spy4JZfIa|IqLIZ<#42~IoDSuXYv=T1(K&aUM
CE&I5nBeG_7B%>~WR8<eK$x$+?bN}v+gf+hBgK5J)vkqfU9)Mcr4t)#&AO9m5cH4iB+SBv)H#fhW
{2I0qAJrhNp;Oi$tk=0)=Bq`}3uys3T{E^!sWUmFj+!0p)ifTL0iOsSW<#ce$h8WSs92@K9q@e*O
;k_H+SW9yooJ{kDy{+#BWFAcjXA4Hjq6em@Yp25Mb_qv79B=zs8+DmxU?-D;!T$~a$`4!HFuL<f{
QEK<L2treFyaoN!+4jPmHrh_TM3%E~u$DBs8nk?5c-)2V0`pywgx%M|UsQ=~>Pp^<Crot;h*M<0$
1I%cxdoVDpD9PC{RBIJ%#;ws;0zTyxu!fp9qPt=y>#LLQBa9r)Bnjb?CqK}j<Rw~!llio1;!kLKH
$=eYmcbk0O$nM7y`=P9aFlwJ4%uTR3u?#0R`GP~?GIk@Y+9<hck+gV6ezl%$BhEer@=kCybKAC7Q
0)q!repB_0q4bq1GIBK!dKL!OQO}zo_O}Rg_G0R>Geb>dreXbYY^i1ixxv5jnv*pdW-QIgDsc~m_
h+VS1_yrMqVZIE<)fMixT-gAuSVxTo?o56BQ-ytwyd_(HrYxcAs-2L)DY;Y0SsnVvLQN+(J>VR6r
zk|`VN~VWYWmhd>$>6A`Upbu%4Rj9oe6<Seka&6wB8O(dB*0tV0SwX=*CSZ(B^GTAu7F`9qMsL89
=Wx>yT0vT_$3z;UF~dZhRjYLNYe-ccUQU+dNe25wbC1}|Dnk~TY&ezd{%ESViDqQi0Pn&L0e0`#-
E`u5#Z`^q4^X+28Q0ok9VE(MdJAZf7i!wA79;0*PgF~*NrT@LW8kfL5g_d7Bwz|;a%8P}r@uvW{+
=BJubz$e-97nP`mo)TZGVp7zz-p#M<j;37SxPcqHRkbMCDl2YW`#uJy1Oc~saN}!|ob}{5$YD>?{
)*0Nx4Bwo%rC^b-gbsd18N8prJ~7l-jQrhZmZ2o&*Fr)&F@$zAK;b#@f|y6$a$iZl;0Zz5$rFv3x
?r$p;~j@FQgh175;eHE&QgFX^tLDK&zxz2+b3TIjf|6yGDCm(4H_{FX+49|Kc-t(q@?Mj>=LuR1c
Tf+yVJ<mQEH*(*V-Ef(xCshCX@2Hdx_8ul=zWDgcE1Lu|9aaET8ogXm(2-iN$F7UUX7eajmHWVz^
ZV>u^+g1y44l+c#0-GvzuZo?*25oGe|H(zNG4l1|NxCpH>W>7zg({hw%8N=IiK-|P8CsZ%&?e;iv
l*|P17*KPo`>=V{R`=$TQI-KrX0F`yyUuWROtv*|pjtA<uqr@aXu})3z7E&nBhVMc;~lD*qW24C0
Vp`ECDvlK7>H>MoCv1AfxVBZV!PTiiE^jVy`pFx$2%@WuXEh7){?N2$Ua{n%`bno*e$s;tcY`ph>
9|lIJ6+daws~6+A4qCwesmEeg6ztrZS>yC<0R&!k>NioJY7K#}S5#SFD)|xFeI5)a??lO0UV!Uyk
z+RAmC&2#{Xz)ml1ECtBX!TMi9d19r^2e9h1u<r8fB0C&XS5>n|Zfkb&KYL8XXWQqoq#rQlpSK@S
PyR}wsXu6qg;Xul*6Y*eqhdR9fX$HM)$p9zgOmdoP1l$$!rPBT)T{<<xk1RE?)5?Wv%ee5SvyFq&
ebdsZPQCtXTf>F8FIcsb8yxY3cI$K3Xr#@dI))>i_Mjt=xvi~d>DnK9rN@qpJBS2;e@l2T-R^dY&
9eOREO$J~wsEv*;<)E+8#4Lr;Q;AkoP=yuih65+c)a<xwX59xwnMw_0l2Mgw3_VzW;J+rav&A{XM
sj}YM5h9mXv$Ybd9k5`nN`MAt`h2yX2q<jp^k0EFUqoHhjq3I1Q=UG)&FXeGjjgsS21`i3l9AX-R
cbT$&}k22jiN${`{24Xu>6--*dksbG-r@|+@@iNUf%F$R_`!R$qi$+c1F7#SH?<hTb^(6G$as<pZ
!fh^I`P5p8f`9g&)NPkGW2|~K1GGQuY7y=7aQDZ|j=Y0fHwkEOoY25|Cv7PT_nml<!y7rhA)yU@T
^0CU;v8mPAR^_`yt08@*&+45^9^$aR=5{7e`S2Su=qo)GL;eYXeouue$;Aj+hp8_ymQN|Ut-6>Nc
b<bfD(WQLvZ#nVLIh8MkD;EG-mgKu8HNqhQ`rEDnTpROr%c)&_{nfsBz(v3t~HQy0|4u8kys*%n@
U?m6H1``igs=;K)TIQ{?SZ%>JRfWtLh;(Hb7bcY$VG^G=!#>)bQ&qDb|xh2TTh*h}}*?E$D3|sfC
UXM8_GF22chD`N1UTNW9q19AI|)VZ@#nr|eonZ@Z=iU=yxXHXz3WRU;m<<R&~*3KiE@)#8z%Q#B%
?SNU7F23TgA&2}x$9poFI9K2r?VJrcbBi!AHD{+e>0+7bAGMpAUM1PR#wWm=d%a`d1BBdGWa)qnz
^GTJfyMJnC3*S6k)f}GxL1nD;!pJcfm<f<9R}_i9bwd|vQl8kh32h4GEJoq31NZm@+%_5eoqIa@J
!e;`&DEAw*-TMagS*)^IlStb3a@&(0$y+aGEej66>?hxGtfunCq{MNc$Vh{mT0*xDz6UMGY=vXb6
_iyMH;PTAO*)6azYz=O4<3MxyljjHiyv&)DH@JWkUJ(IgYCu3?<SPs27Ydr|*0b;cdWG^rL$TVUF
?lM1Ou^{VQvQ9VKl|f$U^SQu%o)7-7EPlkS;T?@|xym|Mt8jn(QHc5?e9rl1o`BV{C6B+a!#N?(a
gUY%-c47>#^qC;67D-z@@%v6b0C6lH?6h;U|{M*A@Maj*Bnp-f{;R$paW}q!CdYSmajlZ<Ez|>aN
TV8sbkJ;j6*3*iA|CAUfRNhYvX7d%(1|U}%=`D>1;)Yc6!0Dlk>wW*Lha%S1$cF1s(MX2<yocqt1
MlO~<#r5?#Ip38f_Xh8@Li?DSC^x)BlEhgRewtD$2TbZ)O=Pde^l025%D}&Z!)8G<G6T#4kg4{$I
ii9PYRw891wDr4Hx8Trlt<%hARuC?eVmREK>U_HU4;#tg??;{*ZacpG<X2rah<W#=?qk^P@xaVad
IOO^0z4@2QKybIH5c7-t`uFj#2^!xp#^H(TN*M_}~XbcG{_t#we{K`sqOm6n6>731s~&Nj^A%`Q=
kA_)Pt7Lvc*h+51y^J@8y6(g}Le)W6*X@2jCIO=xkmb;C~Qj{x2r_(VUD7X!c0aca;$JU|*dZL%|
vu!$Hww~+;u1-U)mtPRLv6_*B*+4<UR`&bpmXy-$@KB9U6&I%n$>ywAHP()@IAX|gpnGV^Qk+{SD
^GhGf;EBMNdLn$QiTJSno$kRwP?v%hE9E<vy&7|{>c-EQHi5g=>f&1N|zH89Vm>8!%L}7t0HiraZ
5Mz_XA&&6ujC<MYE88R2F7=ia(nMaqP@!Xuhx<a&!V-EuAJRo3Esn`h*TSbqO+VVZ*>)e=mU>7#w
Oy0C}%pG4m<e(a@W}Wxi;sv$YK)HXx&@Xd`G6cKoN>1HHpkHCK1y&|v0bx#)1v>)teqxU5W3h~pv
U4w=vczzgZR8=3{WK(ZuZ872)=h*`DJMz>sBKOuodiT;&N0l%2qgj0JUgPpWj)wyTe&$<<IF>ijb
Yo;5Fr;IUJkyGAq&YSepBWJo{H=*zT{*$Pj36dNH6%LnVSJyPTougs%BZxv!bJ7{peGvtxOrg|tJ
ZCJ!i5Acs*vT?S>ADJS0`17xS;B$HGKfXFVyMB8+;p9th<{IB2=dQB$9%kRmfnb7pEInpRK)4O0q
G06Uq#OcCL4Cd)r^y|Mb{ZDOF5gaQo(`XQ>k;GtVs1=&G_kKoFx&?6>0O`Dur3X@JQIhIQbHm0Po
bek5YODbgIMzHff38E(d)Y_5+a1{DI)|0xv=_10q>~E$HG*dD9#@YV?lVw+SX4z{|Vad>1R`Kf(M
K^Spq5@xq~G3UmoX&Ra4CE{l?rU(BTxH;>i?E9#>fg^rT{=H2=0i_!bbzh7YBcmLV($#wSn^3CY=
`PEB|1@B*HZ+>_^dimFLidXL+9rJ_l-(9{wfA{m~yNfs9Ui}qcJ>wVeFJ8WV^U8kJKm7A`24AnvU
wj9hoquz2^)oy^KD^HU`olNhKxaR_xV*xWJ!t;>cNbUhE-vut`=4LGc>5hS(XC!kGqS=lhOS?}sX
g!YsYe(<?eY0{m*2j*cx63*Mk|9^(5`;|{$h0b=0_;?igkI_;~y{Hy*R(Re9gH+tLL&s23Pg?hc_
?ZzJ@`+e^2jdzkdJr{pHo=+c%^4-@T=t1H66*Z;v`Sgn!5I@1!LT;rkIhKZfsrK0ya|c+medh6Y^
xboK6hB!?YTw}ZFv`dPe)oqi7J=a7Dm=;xSzp3%<<{<w$0pIi9T>&kyU`L8ek9ms!&^52pCcP!%@
lvRCnyGqi@NZs)?LLpm63A6v=sX%YCuW>?^p43Pw+T*!e<TAz^U=k$6cEl9EsK<ej>eJ5k7N=G5g
X4zs^q%f)w>t7jJ*r0UnQ`L+&Tg2{tpM~9o5Q=_;pBh*oU7P0y#%%*4pc4?3qM|*zsD`<2Pc;ur)
WF*?$aYVss{RUgUXemD9n;Tc?!$N^!57}ZJGOvZH;v2)h4<VQO+W?#Zd~~q>9|;b_oMUNtTqOQGl
KcwreYEMbl{~$rfawq#LpAS1?t3<>)DlXe96H^u8=cX*?}W<vR|gy5<7QIjPZgZ_nBIqsQgSSGQy
ZP;ZB--i@p6mCe<KQFSYXbtxpBHZULH#wj^L8l!nw9)zrbe8|P8c$upU!PxGGx10Ir(RSy78u7k2
m7+!(@^Zk_k5@!$s6x-0*wa!>i3x3TPLy|gIN-kRDj0fi9=Yvpd@Xg$!7c5hlTiE%8r*~+f&1uRg
1n5eI^K`k#;ZWv4)TPJSEM>fw$JBOHSsvZG~E*4Gc0J%{b7b~F-{xLx!k~mLk1W_vzG;CG;inwnN
ob_lZLCMa-O(AIy;lV;pXk7oda!X>fN(Ls}Y?cU%?z}ZCRd6Fzg8U_9+*4k#6I-<l?9~SvQIiZX;
OTw{jt9((XG6z55#K&tOu;dM-yZYZ{5k@|az&=V(9a@X=8XZPwud*r`&n^cfb<;8V@+MoGMT6}GE
395W9gCK^nAIxcAA?5s)6N<H`$FJ2;ppqb;f%*zOl7<h*#&2r^e1LEm}!-sxq81to|Oyh)3UC+>H
^8;*P>OG<pN$H;eLJ!HM1bFygG821ElN;|)Xt)h4*<iXf(R0>;X$+z6O&v$!sfDG{ga0%%34(K>m
|`CO%JUvHp7S*PrcIb~at>nq0xAh?ks}ef+s|ee17@Nmx!C9Kkco7w@rzR~;J#xTsi=s(JLiiMb@
dd%VnU5Luo}pi??G3D5hu|dNgE(ARfNGL<8`<>POC;&ipAMoIV+5dM?nNlDVvEEutN%NIg@Hy#yd
HaYFfq(1=NRnnZ}vJqN+Fa#kvO9=B?<xiczkhZyejO{PML?7ViKw)w^V|gp%26Zt?g$g?-qko=nT
QDRg0)yKjfGss|=Z_>Wip$&MPfk>A|SFpH*qHLXXL%-oNft#=q$=FEUX6FK3HCULBuXu`VxOm!GG
8nck9;K(Uf1NXYG7)`Ctl<LKkRNj`Wa$+SK=VSSYJI+z&%0W9VqZM~1@~m4^cserxW^+V};O%Xms
trwtf`e?B34mWRm*KuPn<Re!IWuq`Ja=Ci7)~3YceE9=HCnfXrQG;G1kn|)p8j5Bt#%CG`sqjKDM
sL07>&Sc*N=(XY@u~|L~lHxw+~c#TCKHQPFtq2Ygtwy<c5AD8AGRV6cMDkG+L(-3wEB?Zd0rFQDp
9-Ek)^Sm7R+#8e>ehxrzx9zhTxuAG7^t@ZqMHh!*sY0DTaxNL=e}fL{aQ`&<m$yaYQC;f?1<GZ~i
s)<|)UH-V??+jv9_OpQ<R@iwk!GV$2N<%D$)K8)K*;cV-2UKjS0W4>ZIFnE(2AN*?U^KCQ{nuR9*
V=wf`z-qwifKgm1-;c8#Y}7Wjq@sI-G^Qn^enw0`!+I(&Kq#R4Miu<p?`_kYtU#JuNE-=P=BrL?$
`i?{q4q6s9Ng%=>{(uXM#qdX7;j;DcWSg;M!e!?BMt2X9%UZg85vYIzVtkox5Cz6Xx7sLx+}P7Wz
bUVeU^P;ZB%;5www_eL~6*(uq8J(kc4EEibpp{CG@!buQ5Uem&i2$)U=jmoU-Yd7pv<nK<UxqrXj
=mH)8l9R@nA{p^1fUz)T{F2d*{_C<A7dI#ohhP&b*hM9o^_;swIYX{R#v?4t@E#H$k!XlnMA(7Wm
*Ph)j!5HUusWyWog?kOe+s>Wa(HM@<ap~CRek<x$C)ied&H+S#s_(w(au|&9SlhbWn5_vG50fqf(
nm-gC;)M+kAMq5puMzP_oVOb8|H8~;$rux4=M!TFWH}tEvB}%={<}tx`Y<(vw)kZAiZ&Bh)pJiL>
$4ryV%Vx&6>_|7DLW-zukEG=daRhmemC@~M<w>t`9sjwM3%jd4@3U}r|S6+I`2UxtJGFmb*gp{sW
+0T^ebkc4ZJ&Lj|CEUkJuvlBZUy*^`DN$_z?{g03v6kpK4RK6pw12b>FE^6xQ<0b4ss$Py~!U+$y
53o0z6Y)ui5+8mDUs&Qd+Nlidb)goEpM|GP)`=iNrvYXIG+{%=}2OIhuu5&iJL1QPe*PQIU;$L1N
@mM$ymA@yp+gh&D+lU!(~j`*FLR_<*Ui=SRf-w$>f8Bm4}ygLPfPreo{j%npy(8r$=LW;4xjtPln
$K=O<dh<dU7x+=cDLHCL9}g8SOdcwneux5nDbwVVjCYn|L3(^p?jm+z!Kk$eQ~EFgs9ZK$DkE}CD
KQoM5M_p+C6@TB$ypa#3jhTDb)Mzl!oa>FgRx|z-}4CYs$889$!?GtKpsC`x%?Q7%XH0<W7n&i+O
o#<s>~!!yrRic?wc#?S5O-{PuNOk;zA99WJyM!+&1oVkZi?C<7?|Jo8kCmbl#$eZdIVs>ZV6%X`y
VE-(}$4a&{3jd~7mO9C}a#A`gucbQn%P`zDi(rD|H=_ylb&7F??O_ADyHCJ*CzH6(u|n9J1<{1%)
VL9G}2U=P}|?EI<OFy(9gxWV7~!;WSBqCt?5KI0gTP#+p9+47C6OeHc-(wS_sT80{M%?<S@m1e|z
*tT}rbE9Ejl$qIUV=L}h3ExI#KFL)rL$=&E8*SGFQ=ehdXz$FsplaSVA#lU`PwQfzDfd|}TL{CTE
<}D=SLD`KmQhBT+Zqt8E`U1db`buTVDZWJ@o3u2XnfLu#T(@CT4OG{Y*-SE{jYh~wM5+!Z__$#TW
Z<t7X2$8dLJu3>SUX~))iq%O!;`T``Y>_rfSPCy6j}OMsY?-)qcI3-w%a^Hzm%Hn_>Ux__x%AYAs
>v7hGjXxN#{pEVRtE8!)_pz&3V(g2EtE%o}zeFHUYY9WfgfLRCVgoq#8I4g=n+PuaE<rr23m7B|!
;nP+D@xs4Wn9t?EPxKj+rz8wKh)uf|MZ!4m@o%mP^Zw0R}V$Eqovr$FhI~80Zt=A8??yN4S3-6#;
zH}0UZid~#A?1l=r_CMqcF*6=;o#)++Ufh-IT`f&yEN1wQ*PY7G8HP|q>&uMGRc5&GD3aVsrPX5G
7`GZnZb87+1;!5tFj(9riy=QpXy2tte|^<S~a$@K7Y)iX`bHAqpkR}s{Gl;y-Cq1F}t^J(SRsQyO
}6k4L+|9l`Zsv+0CKLdg9q^wzvb4F)b?17S1|c+gr;v+wHy3ga-BOH&rRevx=p&TKH0UqB*ue-)!
yFSAVdTwW*y=bRPW{#zqcA+M6+NV9a+*mVEJspq4jMvKox`H)E+W?r=w_LyJ19ril?I^h)V!Dr<?
(&V1Lro4`!-oeoGIk+$8*1EskRvjMX4-Y%!_ve&Aa_`2#*@4s+#{hdbF-!QuVA3eH_2b&#2q8AZ;
rH|QYP{sKS@zu?i;i0Hz#g1?-5ViYF&ecusFElJ1Nu@;ieKM5YusGPExSrD-!)F}Pi5qH*gOIGF;
pa@yYIxHom%`F#HBKnWquW71*f12H;%D_;v12>!HrM>#-K98goB3z$lldlMr_KTEIJN2KnW-xMTv
3njds#+o_*BYNjD~Dr9Cf@&T$GMpwyvad6*A_ycQ`;Lh|X%gY(G4G4e+<$a)2_FWNWwaI>${<hJm
ez<_A4(S-t%kFq4z{@L6lT^9-b}eA^6)<yf3r>iBk(p355ZbCK*q^pHXOu)Q4f(;v3*(H>qF5%oq
-U<k9h*{wcd_;%LS1k>)NKkUHhR>0pvc^Edyj<ESXaQO_F><*7)3oLfv6BtZ1y0*35{+|HcCa+&Z
uG)?I`lL6z=2nS+gBsxvQJb-?b=SkkH=)h4yQ9!ng*WL@6*ADs_Jym>-eTo2VAu7*tP%fzoASrh<
vedhePResMSC->(8h}e&%8RC&(T}SBML*sBAI-z@oZ|+2Vreb!m1hyv}?vUU`99E`)b2wp9po9nv
M;El4}+o;5R64{p4r6uC}4MFGcTYV|zxVs;_Q6C*`7Ut#nFIl4lJ+|1fPOw-%fnv#@QNRYr44yTO
@c3SY9C$|^q`ObdfNPZt9i{ytQ@@h9Yr>009{`I34z-^9Ns$EziK1z5)38X>7{-JYq|%kz0Of%(d
jHHA7tgL1Z$hQnvF;S9m-fduEri<1pIRL*hpS+rRj7u^<k5PKBh^uL<J0CTGy-h`$$yd?^fF3r5h
o{6;OD4(C|&Yo+yZ;Xe*cqvt-ttN}k{PNiuA|mM-)RTSDymSr{swvTFn0Crs&in9lr%3B~*bu>_7
wD+TK|!VkFt)}{4r^9r-%hft;K4QLWNRaNEAZ4cR>HfXbfy_7r<#31s^zM;;UK%IRU64kW*$#h<;
_!jTR9%J>7A#p>3Y#jy$mu`-wD36<@9umu(mnkz--nGJlLsKH&UU&7t5o0sdExkk`9G3SJ%Sq)#I
ma?=5vVrE)4`Pp2Z#IjO2SoOU03UHD_)>Bnw&u4`g35P{>@NRcF=SVVNUJ6&5h;Tr_a8!XW#E?Y2
0?#?yKWg$JmGB2Z4=A<JEPIkx^bxQfzsCcOS=*U$Nic6=#;FfQMHD*f|QRbinN|x5*K0@;@iprfV
G%rJ!^S1kTeDwBD)i64iPpDPf&aAU}<pK^9vVv6H^*b?^4}H509l@6(uvG?@Lr`r6jOZYJA*ER09
Y~aR>><}HBL}Y_Z3Qzm0NRdjGMyt0XH(NnQkLYmm<#UL{|$Fw5FP
