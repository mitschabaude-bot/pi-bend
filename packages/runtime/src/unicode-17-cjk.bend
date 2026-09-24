# Generated Unicode17 CJK properties; Unicode License V3.
# bit0: NFKC boundary before; bit1: ICU CjkBreakEngine character set.
import Base

def propertiesBelow0(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow2(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow0(code,U32.is_lt(code,768))
    case False{}: propertiesBelow1(code,U32.is_lt(code,848))
def propertiesBelow3(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow4(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow5(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow3(code,U32.is_lt(code,1155))
    case False{}: propertiesBelow4(code,U32.is_lt(code,1425))
def propertiesBelow6(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2(code,U32.is_lt(code,847))
    case False{}: propertiesBelow5(code,U32.is_lt(code,1160))
def propertiesBelow7(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow8(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow9(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow7(code,U32.is_lt(code,1471))
    case False{}: propertiesBelow8(code,U32.is_lt(code,1473))
def propertiesBelow10(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow11(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow12(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow11(code,U32.is_lt(code,1480))
def propertiesBelow13(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow10(code,U32.is_lt(code,1476))
    case False{}: propertiesBelow12(code,U32.is_lt(code,1479))
def propertiesBelow14(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow9(code,U32.is_lt(code,1472))
    case False{}: propertiesBelow13(code,U32.is_lt(code,1478))
def propertiesBelow15(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow6(code,U32.is_lt(code,880))
    case False{}: propertiesBelow14(code,U32.is_lt(code,1475))
def propertiesBelow16(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow17(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow18(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow16(code,U32.is_lt(code,1563))
    case False{}: propertiesBelow17(code,U32.is_lt(code,1632))
def propertiesBelow19(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow20(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow21(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow19(code,U32.is_lt(code,1649))
    case False{}: propertiesBelow20(code,U32.is_lt(code,1757))
def propertiesBelow22(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow18(code,U32.is_lt(code,1611))
    case False{}: propertiesBelow21(code,U32.is_lt(code,1750))
def propertiesBelow23(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow24(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow25(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow23(code,U32.is_lt(code,1765))
    case False{}: propertiesBelow24(code,U32.is_lt(code,1769))
def propertiesBelow26(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow27(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow28(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow27(code,U32.is_lt(code,1840))
def propertiesBelow29(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow26(code,U32.is_lt(code,1774))
    case False{}: propertiesBelow28(code,U32.is_lt(code,1810))
def propertiesBelow30(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow25(code,U32.is_lt(code,1767))
    case False{}: propertiesBelow29(code,U32.is_lt(code,1809))
def propertiesBelow31(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow22(code,U32.is_lt(code,1648))
    case False{}: propertiesBelow30(code,U32.is_lt(code,1770))
def propertiesBelow32(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow15(code,U32.is_lt(code,1470))
    case False{}: propertiesBelow31(code,U32.is_lt(code,1759))
def propertiesBelow33(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow34(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow35(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow33(code,U32.is_lt(code,2027))
    case False{}: propertiesBelow34(code,U32.is_lt(code,2045))
def propertiesBelow36(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow37(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow38(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow36(code,U32.is_lt(code,2070))
    case False{}: propertiesBelow37(code,U32.is_lt(code,2075))
def propertiesBelow39(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow35(code,U32.is_lt(code,2036))
    case False{}: propertiesBelow38(code,U32.is_lt(code,2074))
def propertiesBelow40(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow41(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow42(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow40(code,U32.is_lt(code,2085))
    case False{}: propertiesBelow41(code,U32.is_lt(code,2089))
def propertiesBelow43(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow44(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow45(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow44(code,U32.is_lt(code,2208))
def propertiesBelow46(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow43(code,U32.is_lt(code,2137))
    case False{}: propertiesBelow45(code,U32.is_lt(code,2199))
def propertiesBelow47(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow42(code,U32.is_lt(code,2088))
    case False{}: propertiesBelow46(code,U32.is_lt(code,2140))
def propertiesBelow48(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow39(code,U32.is_lt(code,2046))
    case False{}: propertiesBelow47(code,U32.is_lt(code,2094))
def propertiesBelow49(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow50(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow51(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow49(code,U32.is_lt(code,2274))
    case False{}: propertiesBelow50(code,U32.is_lt(code,2304))
def propertiesBelow52(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow53(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow54(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow53(code,U32.is_lt(code,2385))
def propertiesBelow55(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow52(code,U32.is_lt(code,2365))
    case False{}: propertiesBelow54(code,U32.is_lt(code,2382))
def propertiesBelow56(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow51(code,U32.is_lt(code,2275))
    case False{}: propertiesBelow55(code,U32.is_lt(code,2381))
def propertiesBelow57(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow58(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow59(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow57(code,U32.is_lt(code,2492))
    case False{}: propertiesBelow58(code,U32.is_lt(code,2494))
def propertiesBelow60(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow61(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow62(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow61(code,U32.is_lt(code,2520))
def propertiesBelow63(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow60(code,U32.is_lt(code,2509))
    case False{}: propertiesBelow62(code,U32.is_lt(code,2519))
def propertiesBelow64(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow59(code,U32.is_lt(code,2493))
    case False{}: propertiesBelow63(code,U32.is_lt(code,2510))
def propertiesBelow65(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow56(code,U32.is_lt(code,2364))
    case False{}: propertiesBelow64(code,U32.is_lt(code,2495))
def propertiesBelow66(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow48(code,U32.is_lt(code,2084))
    case False{}: propertiesBelow65(code,U32.is_lt(code,2389))
def propertiesBelow67(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow32(code,U32.is_lt(code,1552))
    case False{}: propertiesBelow66(code,U32.is_lt(code,2250))
def propertiesBelow68(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow69(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow70(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow68(code,U32.is_lt(code,2559))
    case False{}: propertiesBelow69(code,U32.is_lt(code,2621))
def propertiesBelow71(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow72(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow73(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow71(code,U32.is_lt(code,2638))
    case False{}: propertiesBelow72(code,U32.is_lt(code,2749))
def propertiesBelow74(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow70(code,U32.is_lt(code,2620))
    case False{}: propertiesBelow73(code,U32.is_lt(code,2748))
def propertiesBelow75(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow76(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow77(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow75(code,U32.is_lt(code,2766))
    case False{}: propertiesBelow76(code,U32.is_lt(code,2877))
def propertiesBelow78(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow79(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow80(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow79(code,U32.is_lt(code,2902))
def propertiesBelow81(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow78(code,U32.is_lt(code,2879))
    case False{}: propertiesBelow80(code,U32.is_lt(code,2894))
def propertiesBelow82(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow77(code,U32.is_lt(code,2876))
    case False{}: propertiesBelow81(code,U32.is_lt(code,2893))
def propertiesBelow83(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow74(code,U32.is_lt(code,2637))
    case False{}: propertiesBelow82(code,U32.is_lt(code,2878))
def propertiesBelow84(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow85(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow86(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow84(code,U32.is_lt(code,3006))
    case False{}: propertiesBelow85(code,U32.is_lt(code,3021))
def propertiesBelow87(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow88(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow89(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow88(code,U32.is_lt(code,3133))
def propertiesBelow90(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow87(code,U32.is_lt(code,3031))
    case False{}: propertiesBelow89(code,U32.is_lt(code,3132))
def propertiesBelow91(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow86(code,U32.is_lt(code,3007))
    case False{}: propertiesBelow90(code,U32.is_lt(code,3032))
def propertiesBelow92(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow93(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow94(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow92(code,U32.is_lt(code,3150))
    case False{}: propertiesBelow93(code,U32.is_lt(code,3159))
def propertiesBelow95(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow96(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow97(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow96(code,U32.is_lt(code,3277))
def propertiesBelow98(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow95(code,U32.is_lt(code,3261))
    case False{}: propertiesBelow97(code,U32.is_lt(code,3267))
def propertiesBelow99(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow94(code,U32.is_lt(code,3157))
    case False{}: propertiesBelow98(code,U32.is_lt(code,3266))
def propertiesBelow100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow91(code,U32.is_lt(code,3022))
    case False{}: propertiesBelow99(code,U32.is_lt(code,3260))
def propertiesBelow101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow83(code,U32.is_lt(code,2765))
    case False{}: propertiesBelow100(code,U32.is_lt(code,3149))
def propertiesBelow102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow102(code,U32.is_lt(code,3285))
    case False{}: propertiesBelow103(code,U32.is_lt(code,3387))
def propertiesBelow105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow105(code,U32.is_lt(code,3390))
    case False{}: propertiesBelow106(code,U32.is_lt(code,3405))
def propertiesBelow108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow104(code,U32.is_lt(code,3287))
    case False{}: propertiesBelow107(code,U32.is_lt(code,3391))
def propertiesBelow109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow109(code,U32.is_lt(code,3415))
    case False{}: propertiesBelow110(code,U32.is_lt(code,3530))
def propertiesBelow112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow113(code,U32.is_lt(code,3552))
def propertiesBelow115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow112(code,U32.is_lt(code,3535))
    case False{}: propertiesBelow114(code,U32.is_lt(code,3551))
def propertiesBelow116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow111(code,U32.is_lt(code,3416))
    case False{}: propertiesBelow115(code,U32.is_lt(code,3536))
def propertiesBelow117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow108(code,U32.is_lt(code,3389))
    case False{}: propertiesBelow116(code,U32.is_lt(code,3531))
def propertiesBelow118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow118(code,U32.is_lt(code,3643))
    case False{}: propertiesBelow119(code,U32.is_lt(code,3660))
def propertiesBelow121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow122(code,U32.is_lt(code,3864))
def propertiesBelow124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow121(code,U32.is_lt(code,3771))
    case False{}: propertiesBelow123(code,U32.is_lt(code,3788))
def propertiesBelow125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow120(code,U32.is_lt(code,3656))
    case False{}: propertiesBelow124(code,U32.is_lt(code,3784))
def propertiesBelow126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow126(code,U32.is_lt(code,3893))
    case False{}: propertiesBelow127(code,U32.is_lt(code,3895))
def propertiesBelow129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow130(code,U32.is_lt(code,3958))
def propertiesBelow132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow129(code,U32.is_lt(code,3897))
    case False{}: propertiesBelow131(code,U32.is_lt(code,3953))
def propertiesBelow133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow128(code,U32.is_lt(code,3894))
    case False{}: propertiesBelow132(code,U32.is_lt(code,3898))
def propertiesBelow134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow125(code,U32.is_lt(code,3768))
    case False{}: propertiesBelow133(code,U32.is_lt(code,3896))
def propertiesBelow135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow117(code,U32.is_lt(code,3406))
    case False{}: propertiesBelow134(code,U32.is_lt(code,3866))
def propertiesBelow136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow101(code,U32.is_lt(code,2904))
    case False{}: propertiesBelow135(code,U32.is_lt(code,3640))
def propertiesBelow137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow67(code,U32.is_lt(code,1867))
    case False{}: propertiesBelow136(code,U32.is_lt(code,3278))
def propertiesBelow138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow138(code,U32.is_lt(code,3966))
    case False{}: propertiesBelow139(code,U32.is_lt(code,3973))
def propertiesBelow141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow141(code,U32.is_lt(code,3976))
    case False{}: propertiesBelow142(code,U32.is_lt(code,4039))
def propertiesBelow144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow140(code,U32.is_lt(code,3968))
    case False{}: propertiesBelow143(code,U32.is_lt(code,4038))
def propertiesBelow145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow145(code,U32.is_lt(code,4143))
    case False{}: propertiesBelow146(code,U32.is_lt(code,4152))
def propertiesBelow148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow149(code,U32.is_lt(code,4449))
def propertiesBelow151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow148(code,U32.is_lt(code,4155))
    case False{}: propertiesBelow150(code,U32.is_lt(code,4238))
def propertiesBelow152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow147(code,U32.is_lt(code,4151))
    case False{}: propertiesBelow151(code,U32.is_lt(code,4237))
def propertiesBelow153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow144(code,U32.is_lt(code,3974))
    case False{}: propertiesBelow152(code,U32.is_lt(code,4153))
def propertiesBelow154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow154(code,U32.is_lt(code,4520))
    case False{}: propertiesBelow155(code,U32.is_lt(code,4957))
def propertiesBelow157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow158(code,U32.is_lt(code,5941))
def propertiesBelow160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow157(code,U32.is_lt(code,5908))
    case False{}: propertiesBelow159(code,U32.is_lt(code,5940))
def propertiesBelow161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow156(code,U32.is_lt(code,4547))
    case False{}: propertiesBelow160(code,U32.is_lt(code,5910))
def propertiesBelow162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow162(code,U32.is_lt(code,6099))
    case False{}: propertiesBelow163(code,U32.is_lt(code,6110))
def propertiesBelow165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow166(code,U32.is_lt(code,6679))
def propertiesBelow168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow165(code,U32.is_lt(code,6314))
    case False{}: propertiesBelow167(code,U32.is_lt(code,6460))
def propertiesBelow169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow164(code,U32.is_lt(code,6109))
    case False{}: propertiesBelow168(code,U32.is_lt(code,6457))
def propertiesBelow170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow161(code,U32.is_lt(code,4960))
    case False{}: propertiesBelow169(code,U32.is_lt(code,6313))
def propertiesBelow171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow153(code,U32.is_lt(code,4142))
    case False{}: propertiesBelow170(code,U32.is_lt(code,6098))
def propertiesBelow172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow172(code,U32.is_lt(code,6752))
    case False{}: propertiesBelow173(code,U32.is_lt(code,6773))
def propertiesBelow175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow175(code,U32.is_lt(code,6783))
    case False{}: propertiesBelow176(code,U32.is_lt(code,6832))
def propertiesBelow178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow174(code,U32.is_lt(code,6753))
    case False{}: propertiesBelow177(code,U32.is_lt(code,6784))
def propertiesBelow179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow179(code,U32.is_lt(code,6847))
    case False{}: propertiesBelow180(code,U32.is_lt(code,6880))
def propertiesBelow182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow183(code,U32.is_lt(code,6981))
def propertiesBelow185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow182(code,U32.is_lt(code,6964))
    case False{}: propertiesBelow184(code,U32.is_lt(code,6980))
def propertiesBelow186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow181(code,U32.is_lt(code,6878))
    case False{}: propertiesBelow185(code,U32.is_lt(code,6966))
def propertiesBelow187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow178(code,U32.is_lt(code,6781))
    case False{}: propertiesBelow186(code,U32.is_lt(code,6892))
def propertiesBelow188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow188(code,U32.is_lt(code,7028))
    case False{}: propertiesBelow189(code,U32.is_lt(code,7084))
def propertiesBelow191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow192(code,U32.is_lt(code,7223))
def propertiesBelow194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow191(code,U32.is_lt(code,7143))
    case False{}: propertiesBelow193(code,U32.is_lt(code,7156))
def propertiesBelow195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow190(code,U32.is_lt(code,7082))
    case False{}: propertiesBelow194(code,U32.is_lt(code,7154))
def propertiesBelow196(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow197(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow198(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow196(code,U32.is_lt(code,7376))
    case False{}: propertiesBelow197(code,U32.is_lt(code,7380))
def propertiesBelow199(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow200(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow201(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow200(code,U32.is_lt(code,7406))
def propertiesBelow202(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow199(code,U32.is_lt(code,7394))
    case False{}: propertiesBelow201(code,U32.is_lt(code,7405))
def propertiesBelow203(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow198(code,U32.is_lt(code,7379))
    case False{}: propertiesBelow202(code,U32.is_lt(code,7401))
def propertiesBelow204(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow195(code,U32.is_lt(code,7142))
    case False{}: propertiesBelow203(code,U32.is_lt(code,7393))
def propertiesBelow205(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow187(code,U32.is_lt(code,6846))
    case False{}: propertiesBelow204(code,U32.is_lt(code,7224))
def propertiesBelow206(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow171(code,U32.is_lt(code,4470))
    case False{}: propertiesBelow205(code,U32.is_lt(code,7019))
def propertiesBelow207(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow208(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow209(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow207(code,U32.is_lt(code,7413))
    case False{}: propertiesBelow208(code,U32.is_lt(code,7418))
def propertiesBelow210(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow211(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow212(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow210(code,U32.is_lt(code,7680))
    case False{}: propertiesBelow211(code,U32.is_lt(code,8413))
def propertiesBelow213(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow209(code,U32.is_lt(code,7416))
    case False{}: propertiesBelow212(code,U32.is_lt(code,8400))
def propertiesBelow214(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow215(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow216(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow214(code,U32.is_lt(code,8418))
    case False{}: propertiesBelow215(code,U32.is_lt(code,8433))
def propertiesBelow217(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow218(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow219(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow218(code,U32.is_lt(code,11744))
def propertiesBelow220(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow217(code,U32.is_lt(code,11506))
    case False{}: propertiesBelow219(code,U32.is_lt(code,11648))
def propertiesBelow221(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow216(code,U32.is_lt(code,8421))
    case False{}: propertiesBelow220(code,U32.is_lt(code,11647))
def propertiesBelow222(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow213(code,U32.is_lt(code,7616))
    case False{}: propertiesBelow221(code,U32.is_lt(code,11503))
def propertiesBelow223(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow224(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow225(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow223(code,U32.is_lt(code,11904))
    case False{}: propertiesBelow224(code,U32.is_lt(code,11931))
def propertiesBelow226(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow227(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow228(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow227(code,U32.is_lt(code,12294))
def propertiesBelow229(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow226(code,U32.is_lt(code,12032))
    case False{}: propertiesBelow228(code,U32.is_lt(code,12293))
def propertiesBelow230(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow225(code,U32.is_lt(code,11930))
    case False{}: propertiesBelow229(code,U32.is_lt(code,12246))
def propertiesBelow231(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow232(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 0
def propertiesBelow233(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow231(code,U32.is_lt(code,12296))
    case False{}: propertiesBelow232(code,U32.is_lt(code,12330))
def propertiesBelow234(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow235(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow236(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow235(code,U32.is_lt(code,12439))
def propertiesBelow237(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow234(code,U32.is_lt(code,12344))
    case False{}: propertiesBelow236(code,U32.is_lt(code,12353))
def propertiesBelow238(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow233(code,U32.is_lt(code,12321))
    case False{}: propertiesBelow237(code,U32.is_lt(code,12348))
def propertiesBelow239(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow230(code,U32.is_lt(code,12020))
    case False{}: propertiesBelow238(code,U32.is_lt(code,12336))
def propertiesBelow240(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow222(code,U32.is_lt(code,8417))
    case False{}: propertiesBelow239(code,U32.is_lt(code,12295))
def propertiesBelow241(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow242(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow243(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow241(code,U32.is_lt(code,12443))
    case False{}: propertiesBelow242(code,U32.is_lt(code,12448))
def propertiesBelow244(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow245(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow246(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow244(code,U32.is_lt(code,12539))
    case False{}: propertiesBelow245(code,U32.is_lt(code,12544))
def propertiesBelow247(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow243(code,U32.is_lt(code,12445))
    case False{}: propertiesBelow246(code,U32.is_lt(code,12540))
def propertiesBelow248(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow249(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow250(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow248(code,U32.is_lt(code,12596))
    case False{}: propertiesBelow249(code,U32.is_lt(code,12599))
def propertiesBelow251(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow252(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow253(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow252(code,U32.is_lt(code,12784))
def propertiesBelow254(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow251(code,U32.is_lt(code,12608))
    case False{}: propertiesBelow253(code,U32.is_lt(code,12644))
def propertiesBelow255(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow250(code,U32.is_lt(code,12597))
    case False{}: propertiesBelow254(code,U32.is_lt(code,12623))
def propertiesBelow256(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow247(code,U32.is_lt(code,12449))
    case False{}: propertiesBelow255(code,U32.is_lt(code,12602))
def propertiesBelow257(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow258(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow259(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow257(code,U32.is_lt(code,13008))
    case False{}: propertiesBelow258(code,U32.is_lt(code,13056))
def propertiesBelow260(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow261(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow262(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow261(code,U32.is_lt(code,40960))
def propertiesBelow263(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow260(code,U32.is_lt(code,13312))
    case False{}: propertiesBelow262(code,U32.is_lt(code,19968))
def propertiesBelow264(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow259(code,U32.is_lt(code,13055))
    case False{}: propertiesBelow263(code,U32.is_lt(code,19904))
def propertiesBelow265(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow266(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow267(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow265(code,U32.is_lt(code,42608))
    case False{}: propertiesBelow266(code,U32.is_lt(code,42622))
def propertiesBelow268(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow269(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow270(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow269(code,U32.is_lt(code,43014))
def propertiesBelow271(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow268(code,U32.is_lt(code,42656))
    case False{}: propertiesBelow270(code,U32.is_lt(code,42738))
def propertiesBelow272(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow267(code,U32.is_lt(code,42612))
    case False{}: propertiesBelow271(code,U32.is_lt(code,42736))
def propertiesBelow273(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow264(code,U32.is_lt(code,13144))
    case False{}: propertiesBelow272(code,U32.is_lt(code,42654))
def propertiesBelow274(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow256(code,U32.is_lt(code,12595))
    case False{}: propertiesBelow273(code,U32.is_lt(code,42607))
def propertiesBelow275(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow240(code,U32.is_lt(code,11776))
    case False{}: propertiesBelow274(code,U32.is_lt(code,12800))
def propertiesBelow276(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow206(code,U32.is_lt(code,6681))
    case False{}: propertiesBelow275(code,U32.is_lt(code,12441))
def propertiesBelow277(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow137(code,U32.is_lt(code,2558))
    case False{}: propertiesBelow276(code,U32.is_lt(code,7412))
def propertiesBelow278(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow279(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow280(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow278(code,U32.is_lt(code,43052))
    case False{}: propertiesBelow279(code,U32.is_lt(code,43204))
def propertiesBelow281(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow282(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow283(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow281(code,U32.is_lt(code,43232))
    case False{}: propertiesBelow282(code,U32.is_lt(code,43307))
def propertiesBelow284(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow280(code,U32.is_lt(code,43053))
    case False{}: propertiesBelow283(code,U32.is_lt(code,43250))
def propertiesBelow285(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow286(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow287(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow285(code,U32.is_lt(code,43347))
    case False{}: propertiesBelow286(code,U32.is_lt(code,43443))
def propertiesBelow288(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow289(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow290(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow289(code,U32.is_lt(code,43697))
def propertiesBelow291(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow288(code,U32.is_lt(code,43456))
    case False{}: propertiesBelow290(code,U32.is_lt(code,43696))
def propertiesBelow292(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow287(code,U32.is_lt(code,43348))
    case False{}: propertiesBelow291(code,U32.is_lt(code,43457))
def propertiesBelow293(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow284(code,U32.is_lt(code,43205))
    case False{}: propertiesBelow292(code,U32.is_lt(code,43444))
def propertiesBelow294(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow295(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow296(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow294(code,U32.is_lt(code,43701))
    case False{}: propertiesBelow295(code,U32.is_lt(code,43705))
def propertiesBelow297(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow298(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow299(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow297(code,U32.is_lt(code,43712))
    case False{}: propertiesBelow298(code,U32.is_lt(code,43714))
def propertiesBelow300(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow296(code,U32.is_lt(code,43703))
    case False{}: propertiesBelow299(code,U32.is_lt(code,43713))
def propertiesBelow301(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow302(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow303(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow301(code,U32.is_lt(code,43767))
    case False{}: propertiesBelow302(code,U32.is_lt(code,44014))
def propertiesBelow304(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow305(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow306(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: propertiesBelow305(code,U32.is_lt(code,64286))
def propertiesBelow307(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow304(code,U32.is_lt(code,64110))
    case False{}: propertiesBelow306(code,U32.is_lt(code,64218))
def propertiesBelow308(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow303(code,U32.is_lt(code,44013))
    case False{}: propertiesBelow307(code,U32.is_lt(code,64112))
def propertiesBelow309(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow300(code,U32.is_lt(code,43710))
    case False{}: propertiesBelow308(code,U32.is_lt(code,63744))
def propertiesBelow310(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow293(code,U32.is_lt(code,43310))
    case False{}: propertiesBelow309(code,U32.is_lt(code,43766))
def propertiesBelow311(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow312(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow313(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow311(code,U32.is_lt(code,65056))
    case False{}: propertiesBelow312(code,U32.is_lt(code,65382))
def propertiesBelow314(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow315(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow316(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow314(code,U32.is_lt(code,65440))
    case False{}: propertiesBelow315(code,U32.is_lt(code,65444))
def propertiesBelow317(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow313(code,U32.is_lt(code,65072))
    case False{}: propertiesBelow316(code,U32.is_lt(code,65443))
def propertiesBelow318(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow319(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow320(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow318(code,U32.is_lt(code,65447))
    case False{}: propertiesBelow319(code,U32.is_lt(code,65456))
def propertiesBelow321(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow322(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow323(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow322(code,U32.is_lt(code,65490))
def propertiesBelow324(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow321(code,U32.is_lt(code,65480))
    case False{}: propertiesBelow323(code,U32.is_lt(code,65488))
def propertiesBelow325(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow320(code,U32.is_lt(code,65450))
    case False{}: propertiesBelow324(code,U32.is_lt(code,65482))
def propertiesBelow326(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow317(code,U32.is_lt(code,65438))
    case False{}: propertiesBelow325(code,U32.is_lt(code,65474))
def propertiesBelow327(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow328(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow329(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow327(code,U32.is_lt(code,65498))
    case False{}: propertiesBelow328(code,U32.is_lt(code,66045))
def propertiesBelow330(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow331(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow332(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow331(code,U32.is_lt(code,66427))
def propertiesBelow333(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow330(code,U32.is_lt(code,66272))
    case False{}: propertiesBelow332(code,U32.is_lt(code,66422))
def propertiesBelow334(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow329(code,U32.is_lt(code,65501))
    case False{}: propertiesBelow333(code,U32.is_lt(code,66273))
def propertiesBelow335(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow336(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow337(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow335(code,U32.is_lt(code,68110))
    case False{}: propertiesBelow336(code,U32.is_lt(code,68112))
def propertiesBelow338(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow339(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow340(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow339(code,U32.is_lt(code,68325))
def propertiesBelow341(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow338(code,U32.is_lt(code,68155))
    case False{}: propertiesBelow340(code,U32.is_lt(code,68160))
def propertiesBelow342(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow337(code,U32.is_lt(code,68111))
    case False{}: propertiesBelow341(code,U32.is_lt(code,68159))
def propertiesBelow343(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow334(code,U32.is_lt(code,66046))
    case False{}: propertiesBelow342(code,U32.is_lt(code,68152))
def propertiesBelow344(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow326(code,U32.is_lt(code,65445))
    case False{}: propertiesBelow343(code,U32.is_lt(code,68109))
def propertiesBelow345(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow310(code,U32.is_lt(code,43698))
    case False{}: propertiesBelow344(code,U32.is_lt(code,65496))
def propertiesBelow346(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow347(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow348(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow346(code,U32.is_lt(code,68900))
    case False{}: propertiesBelow347(code,U32.is_lt(code,68969))
def propertiesBelow349(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow350(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow351(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow349(code,U32.is_lt(code,69291))
    case False{}: propertiesBelow350(code,U32.is_lt(code,69370))
def propertiesBelow352(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow348(code,U32.is_lt(code,68904))
    case False{}: propertiesBelow351(code,U32.is_lt(code,69293))
def propertiesBelow353(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow354(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow355(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow353(code,U32.is_lt(code,69373))
    case False{}: propertiesBelow354(code,U32.is_lt(code,69446))
def propertiesBelow356(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow357(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow358(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow357(code,U32.is_lt(code,69703))
def propertiesBelow359(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow356(code,U32.is_lt(code,69506))
    case False{}: propertiesBelow358(code,U32.is_lt(code,69702))
def propertiesBelow360(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow355(code,U32.is_lt(code,69376))
    case False{}: propertiesBelow359(code,U32.is_lt(code,69510))
def propertiesBelow361(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow352(code,U32.is_lt(code,68974))
    case False{}: propertiesBelow360(code,U32.is_lt(code,69457))
def propertiesBelow362(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow363(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow364(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow362(code,U32.is_lt(code,69745))
    case False{}: propertiesBelow363(code,U32.is_lt(code,69760))
def propertiesBelow365(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow366(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow367(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow366(code,U32.is_lt(code,69927))
def propertiesBelow368(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow365(code,U32.is_lt(code,69819))
    case False{}: propertiesBelow367(code,U32.is_lt(code,69891))
def propertiesBelow369(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow364(code,U32.is_lt(code,69759))
    case False{}: propertiesBelow368(code,U32.is_lt(code,69888))
def propertiesBelow370(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow371(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow372(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow370(code,U32.is_lt(code,69939))
    case False{}: propertiesBelow371(code,U32.is_lt(code,70003))
def propertiesBelow373(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow374(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow375(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow374(code,U32.is_lt(code,70091))
def propertiesBelow376(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow373(code,U32.is_lt(code,70080))
    case False{}: propertiesBelow375(code,U32.is_lt(code,70090))
def propertiesBelow377(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow372(code,U32.is_lt(code,69941))
    case False{}: propertiesBelow376(code,U32.is_lt(code,70081))
def propertiesBelow378(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow369(code,U32.is_lt(code,69817))
    case False{}: propertiesBelow377(code,U32.is_lt(code,70004))
def propertiesBelow379(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow361(code,U32.is_lt(code,69372))
    case False{}: propertiesBelow378(code,U32.is_lt(code,69928))
def propertiesBelow380(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow381(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow382(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow380(code,U32.is_lt(code,70199))
    case False{}: propertiesBelow381(code,U32.is_lt(code,70379))
def propertiesBelow383(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow384(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow385(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow383(code,U32.is_lt(code,70461))
    case False{}: propertiesBelow384(code,U32.is_lt(code,70463))
def propertiesBelow386(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow382(code,U32.is_lt(code,70377))
    case False{}: propertiesBelow385(code,U32.is_lt(code,70462))
def propertiesBelow387(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow388(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow389(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow387(code,U32.is_lt(code,70478))
    case False{}: propertiesBelow388(code,U32.is_lt(code,70488))
def propertiesBelow390(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow391(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow392(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow391(code,U32.is_lt(code,70584))
def propertiesBelow393(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow390(code,U32.is_lt(code,70509))
    case False{}: propertiesBelow392(code,U32.is_lt(code,70517))
def propertiesBelow394(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow389(code,U32.is_lt(code,70487))
    case False{}: propertiesBelow393(code,U32.is_lt(code,70512))
def propertiesBelow395(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow386(code,U32.is_lt(code,70459))
    case False{}: propertiesBelow394(code,U32.is_lt(code,70502))
def propertiesBelow396(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow397(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow398(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow396(code,U32.is_lt(code,70587))
    case False{}: propertiesBelow397(code,U32.is_lt(code,70594))
def propertiesBelow399(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow400(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow401(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow400(code,U32.is_lt(code,70602))
def propertiesBelow402(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow399(code,U32.is_lt(code,70597))
    case False{}: propertiesBelow401(code,U32.is_lt(code,70599))
def propertiesBelow403(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow398(code,U32.is_lt(code,70588))
    case False{}: propertiesBelow402(code,U32.is_lt(code,70598))
def propertiesBelow404(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow405(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow406(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow404(code,U32.is_lt(code,70609))
    case False{}: propertiesBelow405(code,U32.is_lt(code,70723))
def propertiesBelow407(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow408(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow409(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow408(code,U32.is_lt(code,70832))
def propertiesBelow410(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow407(code,U32.is_lt(code,70727))
    case False{}: propertiesBelow409(code,U32.is_lt(code,70751))
def propertiesBelow411(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow406(code,U32.is_lt(code,70722))
    case False{}: propertiesBelow410(code,U32.is_lt(code,70750))
def propertiesBelow412(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow403(code,U32.is_lt(code,70595))
    case False{}: propertiesBelow411(code,U32.is_lt(code,70726))
def propertiesBelow413(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow395(code,U32.is_lt(code,70477))
    case False{}: propertiesBelow412(code,U32.is_lt(code,70606))
def propertiesBelow414(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow379(code,U32.is_lt(code,69744))
    case False{}: propertiesBelow413(code,U32.is_lt(code,70585))
def propertiesBelow415(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow345(code,U32.is_lt(code,64287))
    case False{}: propertiesBelow414(code,U32.is_lt(code,70197))
def propertiesBelow416(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow417(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow418(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow416(code,U32.is_lt(code,70842))
    case False{}: propertiesBelow417(code,U32.is_lt(code,70845))
def propertiesBelow419(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow420(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow421(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow419(code,U32.is_lt(code,70850))
    case False{}: propertiesBelow420(code,U32.is_lt(code,71087))
def propertiesBelow422(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow418(code,U32.is_lt(code,70843))
    case False{}: propertiesBelow421(code,U32.is_lt(code,70852))
def propertiesBelow423(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow424(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow425(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow423(code,U32.is_lt(code,71103))
    case False{}: propertiesBelow424(code,U32.is_lt(code,71231))
def propertiesBelow426(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow427(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow428(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow427(code,U32.is_lt(code,71468))
def propertiesBelow429(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow426(code,U32.is_lt(code,71350))
    case False{}: propertiesBelow428(code,U32.is_lt(code,71467))
def propertiesBelow430(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow425(code,U32.is_lt(code,71105))
    case False{}: propertiesBelow429(code,U32.is_lt(code,71352))
def propertiesBelow431(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow422(code,U32.is_lt(code,70846))
    case False{}: propertiesBelow430(code,U32.is_lt(code,71232))
def propertiesBelow432(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow433(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow434(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow432(code,U32.is_lt(code,71739))
    case False{}: propertiesBelow433(code,U32.is_lt(code,71985))
def propertiesBelow435(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow436(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow437(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow436(code,U32.is_lt(code,72160))
def propertiesBelow438(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow435(code,U32.is_lt(code,71999))
    case False{}: propertiesBelow437(code,U32.is_lt(code,72004))
def propertiesBelow439(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow434(code,U32.is_lt(code,71984))
    case False{}: propertiesBelow438(code,U32.is_lt(code,72003))
def propertiesBelow440(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow441(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow442(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow440(code,U32.is_lt(code,72244))
    case False{}: propertiesBelow441(code,U32.is_lt(code,72263))
def propertiesBelow443(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow444(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow445(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow444(code,U32.is_lt(code,72768))
def propertiesBelow446(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow443(code,U32.is_lt(code,72345))
    case False{}: propertiesBelow445(code,U32.is_lt(code,72767))
def propertiesBelow447(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow442(code,U32.is_lt(code,72245))
    case False{}: propertiesBelow446(code,U32.is_lt(code,72346))
def propertiesBelow448(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow439(code,U32.is_lt(code,71997))
    case False{}: propertiesBelow447(code,U32.is_lt(code,72264))
def propertiesBelow449(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow431(code,U32.is_lt(code,71088))
    case False{}: propertiesBelow448(code,U32.is_lt(code,72161))
def propertiesBelow450(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow451(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow452(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow450(code,U32.is_lt(code,73027))
    case False{}: propertiesBelow451(code,U32.is_lt(code,73030))
def propertiesBelow453(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow454(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow455(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow453(code,U32.is_lt(code,73112))
    case False{}: propertiesBelow454(code,U32.is_lt(code,73539))
def propertiesBelow456(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow452(code,U32.is_lt(code,73028))
    case False{}: propertiesBelow455(code,U32.is_lt(code,73537))
def propertiesBelow457(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow458(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow459(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow457(code,U32.is_lt(code,90410))
    case False{}: propertiesBelow458(code,U32.is_lt(code,90416))
def propertiesBelow460(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow461(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow462(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow461(code,U32.is_lt(code,93543))
def propertiesBelow463(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow460(code,U32.is_lt(code,92917))
    case False{}: propertiesBelow462(code,U32.is_lt(code,92983))
def propertiesBelow464(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow459(code,U32.is_lt(code,90415))
    case False{}: propertiesBelow463(code,U32.is_lt(code,92976))
def propertiesBelow465(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow456(code,U32.is_lt(code,73111))
    case False{}: propertiesBelow464(code,U32.is_lt(code,92912))
def propertiesBelow466(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow467(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 2
def propertiesBelow468(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow466(code,U32.is_lt(code,94178))
    case False{}: propertiesBelow467(code,U32.is_lt(code,94192))
def propertiesBelow469(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow470(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow471(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: propertiesBelow470(code,U32.is_lt(code,110581))
def propertiesBelow472(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow469(code,U32.is_lt(code,94199))
    case False{}: propertiesBelow471(code,U32.is_lt(code,110580))
def propertiesBelow473(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow468(code,U32.is_lt(code,94180))
    case False{}: propertiesBelow472(code,U32.is_lt(code,110576))
def propertiesBelow474(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow475(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow476(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow474(code,U32.is_lt(code,110589))
    case False{}: propertiesBelow475(code,U32.is_lt(code,110592))
def propertiesBelow477(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow478(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow479(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow478(code,U32.is_lt(code,110931))
def propertiesBelow480(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow477(code,U32.is_lt(code,110898))
    case False{}: propertiesBelow479(code,U32.is_lt(code,110928))
def propertiesBelow481(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow476(code,U32.is_lt(code,110591))
    case False{}: propertiesBelow480(code,U32.is_lt(code,110899))
def propertiesBelow482(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow473(code,U32.is_lt(code,94194))
    case False{}: propertiesBelow481(code,U32.is_lt(code,110883))
def propertiesBelow483(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow465(code,U32.is_lt(code,90398))
    case False{}: propertiesBelow482(code,U32.is_lt(code,110588))
def propertiesBelow484(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow449(code,U32.is_lt(code,71737))
    case False{}: propertiesBelow483(code,U32.is_lt(code,93545))
def propertiesBelow485(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow486(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow487(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow485(code,U32.is_lt(code,110934))
    case False{}: propertiesBelow486(code,U32.is_lt(code,110952))
def propertiesBelow488(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow489(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow490(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow488(code,U32.is_lt(code,113823))
    case False{}: propertiesBelow489(code,U32.is_lt(code,119146))
def propertiesBelow491(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow487(code,U32.is_lt(code,110948))
    case False{}: propertiesBelow490(code,U32.is_lt(code,119141))
def propertiesBelow492(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow493(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow494(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow492(code,U32.is_lt(code,119155))
    case False{}: propertiesBelow493(code,U32.is_lt(code,119171))
def propertiesBelow495(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow496(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow497(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow496(code,U32.is_lt(code,119362))
def propertiesBelow498(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow495(code,U32.is_lt(code,119180))
    case False{}: propertiesBelow497(code,U32.is_lt(code,119214))
def propertiesBelow499(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow494(code,U32.is_lt(code,119163))
    case False{}: propertiesBelow498(code,U32.is_lt(code,119210))
def propertiesBelow500(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow491(code,U32.is_lt(code,113822))
    case False{}: propertiesBelow499(code,U32.is_lt(code,119173))
def propertiesBelow501(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow502(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow503(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow501(code,U32.is_lt(code,122880))
    case False{}: propertiesBelow502(code,U32.is_lt(code,122888))
def propertiesBelow504(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow505(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow506(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow505(code,U32.is_lt(code,122917))
def propertiesBelow507(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow504(code,U32.is_lt(code,122907))
    case False{}: propertiesBelow506(code,U32.is_lt(code,122915))
def propertiesBelow508(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow503(code,U32.is_lt(code,122887))
    case False{}: propertiesBelow507(code,U32.is_lt(code,122914))
def propertiesBelow509(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow510(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow511(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow509(code,U32.is_lt(code,122923))
    case False{}: propertiesBelow510(code,U32.is_lt(code,123024))
def propertiesBelow512(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow513(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow514(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow513(code,U32.is_lt(code,123628))
def propertiesBelow515(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow512(code,U32.is_lt(code,123191))
    case False{}: propertiesBelow514(code,U32.is_lt(code,123567))
def propertiesBelow516(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow511(code,U32.is_lt(code,123023))
    case False{}: propertiesBelow515(code,U32.is_lt(code,123566))
def propertiesBelow517(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow508(code,U32.is_lt(code,122905))
    case False{}: propertiesBelow516(code,U32.is_lt(code,123184))
def propertiesBelow518(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow500(code,U32.is_lt(code,119149))
    case False{}: propertiesBelow517(code,U32.is_lt(code,122918))
def propertiesBelow519(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow520(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow521(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow519(code,U32.is_lt(code,124140))
    case False{}: propertiesBelow520(code,U32.is_lt(code,124398))
def propertiesBelow522(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow523(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow524(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow522(code,U32.is_lt(code,124643))
    case False{}: propertiesBelow523(code,U32.is_lt(code,124646))
def propertiesBelow525(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow521(code,U32.is_lt(code,124144))
    case False{}: propertiesBelow524(code,U32.is_lt(code,124644))
def propertiesBelow526(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow527(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow528(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow526(code,U32.is_lt(code,124654))
    case False{}: propertiesBelow527(code,U32.is_lt(code,124661))
def propertiesBelow529(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow530(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow531(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow530(code,U32.is_lt(code,125259))
def propertiesBelow532(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow529(code,U32.is_lt(code,125136))
    case False{}: propertiesBelow531(code,U32.is_lt(code,125252))
def propertiesBelow533(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow528(code,U32.is_lt(code,124656))
    case False{}: propertiesBelow532(code,U32.is_lt(code,125143))
def propertiesBelow534(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow525(code,U32.is_lt(code,124400))
    case False{}: propertiesBelow533(code,U32.is_lt(code,124662))
def propertiesBelow535(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow536(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow537(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow535(code,U32.is_lt(code,127489))
    case False{}: propertiesBelow536(code,U32.is_lt(code,173792))
def propertiesBelow538(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow539(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow540(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: propertiesBelow539(code,U32.is_lt(code,183984))
def propertiesBelow541(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow538(code,U32.is_lt(code,178206))
    case False{}: propertiesBelow540(code,U32.is_lt(code,183982))
def propertiesBelow542(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow537(code,U32.is_lt(code,131072))
    case False{}: propertiesBelow541(code,U32.is_lt(code,178208))
def propertiesBelow543(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow544(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow545(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow543(code,U32.is_lt(code,191472))
    case False{}: propertiesBelow544(code,U32.is_lt(code,194560))
def propertiesBelow546(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow547(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow548(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow547(code,U32.is_lt(code,210042))
def propertiesBelow549(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow546(code,U32.is_lt(code,196608))
    case False{}: propertiesBelow548(code,U32.is_lt(code,201552))
def propertiesBelow550(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow545(code,U32.is_lt(code,192094))
    case False{}: propertiesBelow549(code,U32.is_lt(code,201547))
def propertiesBelow551(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow542(code,U32.is_lt(code,173824))
    case False{}: propertiesBelow550(code,U32.is_lt(code,195102))
def propertiesBelow552(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow534(code,U32.is_lt(code,124647))
    case False{}: propertiesBelow551(code,U32.is_lt(code,191457))
def propertiesBelow553(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow518(code,U32.is_lt(code,119365))
    case False{}: propertiesBelow552(code,U32.is_lt(code,127488))
def propertiesBelow554(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow484(code,U32.is_lt(code,73026))
    case False{}: propertiesBelow553(code,U32.is_lt(code,123632))
def propertiesBelow555(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow415(code,U32.is_lt(code,68327))
    case False{}: propertiesBelow554(code,U32.is_lt(code,110933))
def propertiesBelow556(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow277(code,U32.is_lt(code,3962))
    case False{}: propertiesBelow555(code,U32.is_lt(code,70833))

def properties(+code: U32) -> U32:
  propertiesBelow556(code,U32.is_lt(code,43015))
