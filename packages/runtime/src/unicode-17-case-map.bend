# Generated from pinned Unicode17 UCD by scripts/generate-case-map.py.
# Unicode License V3; see unicode-LICENSE.txt.
import Base

def propertiesBelow0(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow2(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow0(code,U32.is_lt(code,39))
    case False{}: propertiesBelow1(code,U32.is_lt(code,46))
def propertiesBelow3(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow4(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow5(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow4(code,U32.is_lt(code,91))
def propertiesBelow6(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow3(code,U32.is_lt(code,58))
    case False{}: propertiesBelow5(code,U32.is_lt(code,65))
def propertiesBelow7(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2(code,U32.is_lt(code,40))
    case False{}: propertiesBelow6(code,U32.is_lt(code,59))
def propertiesBelow8(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow9(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow10(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow8(code,U32.is_lt(code,95))
    case False{}: propertiesBelow9(code,U32.is_lt(code,97))
def propertiesBelow11(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow12(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow13(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow12(code,U32.is_lt(code,171))
def propertiesBelow14(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow11(code,U32.is_lt(code,168))
    case False{}: propertiesBelow13(code,U32.is_lt(code,170))
def propertiesBelow15(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow10(code,U32.is_lt(code,96))
    case False{}: propertiesBelow14(code,U32.is_lt(code,169))
def propertiesBelow16(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow7(code,U32.is_lt(code,47))
    case False{}: propertiesBelow15(code,U32.is_lt(code,123))
def propertiesBelow17(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow18(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow19(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow17(code,U32.is_lt(code,174))
    case False{}: propertiesBelow18(code,U32.is_lt(code,176))
def propertiesBelow20(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow21(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow22(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow21(code,U32.is_lt(code,185))
def propertiesBelow23(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow20(code,U32.is_lt(code,181))
    case False{}: propertiesBelow22(code,U32.is_lt(code,183))
def propertiesBelow24(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow19(code,U32.is_lt(code,175))
    case False{}: propertiesBelow23(code,U32.is_lt(code,182))
def propertiesBelow25(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow26(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow27(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow26(code,U32.is_lt(code,216))
def propertiesBelow28(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow25(code,U32.is_lt(code,187))
    case False{}: propertiesBelow27(code,U32.is_lt(code,215))
def propertiesBelow29(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow30(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow31(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow30(code,U32.is_lt(code,448))
def propertiesBelow32(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow29(code,U32.is_lt(code,248))
    case False{}: propertiesBelow31(code,U32.is_lt(code,444))
def propertiesBelow33(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow28(code,U32.is_lt(code,192))
    case False{}: propertiesBelow32(code,U32.is_lt(code,443))
def propertiesBelow34(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow24(code,U32.is_lt(code,180))
    case False{}: propertiesBelow33(code,U32.is_lt(code,247))
def propertiesBelow35(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow16(code,U32.is_lt(code,94))
    case False{}: propertiesBelow34(code,U32.is_lt(code,186))
def propertiesBelow36(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow37(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow38(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow36(code,U32.is_lt(code,660))
    case False{}: propertiesBelow37(code,U32.is_lt(code,688))
def propertiesBelow39(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 3
def propertiesBelow40(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 2
def propertiesBelow41(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow40(code,U32.is_lt(code,741))
def propertiesBelow42(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow39(code,U32.is_lt(code,704))
    case False{}: propertiesBelow41(code,U32.is_lt(code,736))
def propertiesBelow43(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow38(code,U32.is_lt(code,662))
    case False{}: propertiesBelow42(code,U32.is_lt(code,706))
def propertiesBelow44(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 2
def propertiesBelow45(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 2
def propertiesBelow46(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow44(code,U32.is_lt(code,838))
    case False{}: propertiesBelow45(code,U32.is_lt(code,884))
def propertiesBelow47(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow48(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow49(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: propertiesBelow48(code,U32.is_lt(code,894))
def propertiesBelow50(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow47(code,U32.is_lt(code,888))
    case False{}: propertiesBelow49(code,U32.is_lt(code,891))
def propertiesBelow51(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow46(code,U32.is_lt(code,880))
    case False{}: propertiesBelow50(code,U32.is_lt(code,890))
def propertiesBelow52(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow43(code,U32.is_lt(code,697))
    case False{}: propertiesBelow51(code,U32.is_lt(code,886))
def propertiesBelow53(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow54(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow55(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow53(code,U32.is_lt(code,896))
    case False{}: propertiesBelow54(code,U32.is_lt(code,902))
def propertiesBelow56(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow57(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow58(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow57(code,U32.is_lt(code,909))
def propertiesBelow59(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow56(code,U32.is_lt(code,904))
    case False{}: propertiesBelow58(code,U32.is_lt(code,908))
def propertiesBelow60(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow55(code,U32.is_lt(code,900))
    case False{}: propertiesBelow59(code,U32.is_lt(code,907))
def propertiesBelow61(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow62(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow63(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow62(code,U32.is_lt(code,1015))
def propertiesBelow64(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow61(code,U32.is_lt(code,930))
    case False{}: propertiesBelow63(code,U32.is_lt(code,1014))
def propertiesBelow65(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow66(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow67(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow66(code,U32.is_lt(code,1329))
def propertiesBelow68(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow65(code,U32.is_lt(code,1155))
    case False{}: propertiesBelow67(code,U32.is_lt(code,1328))
def propertiesBelow69(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow64(code,U32.is_lt(code,931))
    case False{}: propertiesBelow68(code,U32.is_lt(code,1162))
def propertiesBelow70(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow60(code,U32.is_lt(code,903))
    case False{}: propertiesBelow69(code,U32.is_lt(code,1154))
def propertiesBelow71(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow52(code,U32.is_lt(code,837))
    case False{}: propertiesBelow70(code,U32.is_lt(code,910))
def propertiesBelow72(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow35(code,U32.is_lt(code,173))
    case False{}: propertiesBelow71(code,U32.is_lt(code,895))
def propertiesBelow73(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow74(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow75(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow73(code,U32.is_lt(code,1369))
    case False{}: propertiesBelow74(code,U32.is_lt(code,1375))
def propertiesBelow76(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow77(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow78(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow77(code,U32.is_lt(code,1471))
def propertiesBelow79(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow76(code,U32.is_lt(code,1417))
    case False{}: propertiesBelow78(code,U32.is_lt(code,1470))
def propertiesBelow80(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow75(code,U32.is_lt(code,1370))
    case False{}: propertiesBelow79(code,U32.is_lt(code,1425))
def propertiesBelow81(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow82(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow83(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow81(code,U32.is_lt(code,1473))
    case False{}: propertiesBelow82(code,U32.is_lt(code,1476))
def propertiesBelow84(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow85(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow86(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow85(code,U32.is_lt(code,1525))
def propertiesBelow87(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow84(code,U32.is_lt(code,1479))
    case False{}: propertiesBelow86(code,U32.is_lt(code,1524))
def propertiesBelow88(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow83(code,U32.is_lt(code,1475))
    case False{}: propertiesBelow87(code,U32.is_lt(code,1480))
def propertiesBelow89(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow80(code,U32.is_lt(code,1376))
    case False{}: propertiesBelow88(code,U32.is_lt(code,1478))
def propertiesBelow90(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow91(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow92(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow90(code,U32.is_lt(code,1542))
    case False{}: propertiesBelow91(code,U32.is_lt(code,1563))
def propertiesBelow93(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow94(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow95(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow94(code,U32.is_lt(code,1611))
def propertiesBelow96(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow93(code,U32.is_lt(code,1565))
    case False{}: propertiesBelow95(code,U32.is_lt(code,1601))
def propertiesBelow97(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow92(code,U32.is_lt(code,1552))
    case False{}: propertiesBelow96(code,U32.is_lt(code,1600))
def propertiesBelow98(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow99(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow99(code,U32.is_lt(code,1758))
def propertiesBelow101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow98(code,U32.is_lt(code,1648))
    case False{}: propertiesBelow100(code,U32.is_lt(code,1750))
def propertiesBelow102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow103(code,U32.is_lt(code,1807))
def propertiesBelow105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow102(code,U32.is_lt(code,1769))
    case False{}: propertiesBelow104(code,U32.is_lt(code,1774))
def propertiesBelow106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow101(code,U32.is_lt(code,1649))
    case False{}: propertiesBelow105(code,U32.is_lt(code,1770))
def propertiesBelow107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow97(code,U32.is_lt(code,1564))
    case False{}: propertiesBelow106(code,U32.is_lt(code,1759))
def propertiesBelow108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow89(code,U32.is_lt(code,1472))
    case False{}: propertiesBelow107(code,U32.is_lt(code,1632))
def propertiesBelow109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow109(code,U32.is_lt(code,1809))
    case False{}: propertiesBelow110(code,U32.is_lt(code,1840))
def propertiesBelow112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow113(code,U32.is_lt(code,2038))
def propertiesBelow115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow112(code,U32.is_lt(code,1958))
    case False{}: propertiesBelow114(code,U32.is_lt(code,2027))
def propertiesBelow116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow111(code,U32.is_lt(code,1810))
    case False{}: propertiesBelow115(code,U32.is_lt(code,1969))
def propertiesBelow117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow118(code,U32.is_lt(code,2070))
def propertiesBelow120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow117(code,U32.is_lt(code,2043))
    case False{}: propertiesBelow119(code,U32.is_lt(code,2046))
def propertiesBelow121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow122(code,U32.is_lt(code,2185))
def propertiesBelow124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow121(code,U32.is_lt(code,2137))
    case False{}: propertiesBelow123(code,U32.is_lt(code,2184))
def propertiesBelow125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow120(code,U32.is_lt(code,2045))
    case False{}: propertiesBelow124(code,U32.is_lt(code,2140))
def propertiesBelow126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow116(code,U32.is_lt(code,1867))
    case False{}: propertiesBelow125(code,U32.is_lt(code,2094))
def propertiesBelow127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow127(code,U32.is_lt(code,2194))
    case False{}: propertiesBelow128(code,U32.is_lt(code,2208))
def propertiesBelow130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow131(code,U32.is_lt(code,2364))
def propertiesBelow133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow130(code,U32.is_lt(code,2307))
    case False{}: propertiesBelow132(code,U32.is_lt(code,2363))
def propertiesBelow134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow129(code,U32.is_lt(code,2199))
    case False{}: propertiesBelow133(code,U32.is_lt(code,2362))
def propertiesBelow135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow136(code,U32.is_lt(code,2382))
def propertiesBelow138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow135(code,U32.is_lt(code,2369))
    case False{}: propertiesBelow137(code,U32.is_lt(code,2381))
def propertiesBelow139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow140(code,U32.is_lt(code,2417))
def propertiesBelow142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow139(code,U32.is_lt(code,2392))
    case False{}: propertiesBelow141(code,U32.is_lt(code,2404))
def propertiesBelow143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow138(code,U32.is_lt(code,2377))
    case False{}: propertiesBelow142(code,U32.is_lt(code,2402))
def propertiesBelow144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow134(code,U32.is_lt(code,2249))
    case False{}: propertiesBelow143(code,U32.is_lt(code,2385))
def propertiesBelow145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow126(code,U32.is_lt(code,2042))
    case False{}: propertiesBelow144(code,U32.is_lt(code,2365))
def propertiesBelow146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow108(code,U32.is_lt(code,1536))
    case False{}: propertiesBelow145(code,U32.is_lt(code,2192))
def propertiesBelow147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow72(code,U32.is_lt(code,452))
    case False{}: propertiesBelow146(code,U32.is_lt(code,1808))
def propertiesBelow148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow148(code,U32.is_lt(code,2433))
    case False{}: propertiesBelow149(code,U32.is_lt(code,2492))
def propertiesBelow151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow152(code,U32.is_lt(code,2510))
def propertiesBelow154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow151(code,U32.is_lt(code,2497))
    case False{}: propertiesBelow153(code,U32.is_lt(code,2509))
def propertiesBelow155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow150(code,U32.is_lt(code,2434))
    case False{}: propertiesBelow154(code,U32.is_lt(code,2501))
def propertiesBelow156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow156(code,U32.is_lt(code,2532))
    case False{}: propertiesBelow157(code,U32.is_lt(code,2559))
def propertiesBelow159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow160(code,U32.is_lt(code,2625))
def propertiesBelow162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow159(code,U32.is_lt(code,2563))
    case False{}: propertiesBelow161(code,U32.is_lt(code,2621))
def propertiesBelow163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow158(code,U32.is_lt(code,2558))
    case False{}: propertiesBelow162(code,U32.is_lt(code,2620))
def propertiesBelow164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow155(code,U32.is_lt(code,2493))
    case False{}: propertiesBelow163(code,U32.is_lt(code,2561))
def propertiesBelow165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow165(code,U32.is_lt(code,2631))
    case False{}: propertiesBelow166(code,U32.is_lt(code,2635))
def propertiesBelow168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow169(code,U32.is_lt(code,2674))
def propertiesBelow171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow168(code,U32.is_lt(code,2641))
    case False{}: propertiesBelow170(code,U32.is_lt(code,2672))
def propertiesBelow172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow167(code,U32.is_lt(code,2633))
    case False{}: propertiesBelow171(code,U32.is_lt(code,2642))
def propertiesBelow173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow174(code,U32.is_lt(code,2748))
def propertiesBelow176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow173(code,U32.is_lt(code,2678))
    case False{}: propertiesBelow175(code,U32.is_lt(code,2691))
def propertiesBelow177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow178(code,U32.is_lt(code,2761))
def propertiesBelow180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow177(code,U32.is_lt(code,2753))
    case False{}: propertiesBelow179(code,U32.is_lt(code,2759))
def propertiesBelow181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow176(code,U32.is_lt(code,2689))
    case False{}: propertiesBelow180(code,U32.is_lt(code,2758))
def propertiesBelow182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow172(code,U32.is_lt(code,2638))
    case False{}: propertiesBelow181(code,U32.is_lt(code,2749))
def propertiesBelow183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow164(code,U32.is_lt(code,2530))
    case False{}: propertiesBelow182(code,U32.is_lt(code,2677))
def propertiesBelow184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow184(code,U32.is_lt(code,2766))
    case False{}: propertiesBelow185(code,U32.is_lt(code,2788))
def propertiesBelow187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow188(code,U32.is_lt(code,2876))
def propertiesBelow190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow187(code,U32.is_lt(code,2816))
    case False{}: propertiesBelow189(code,U32.is_lt(code,2818))
def propertiesBelow191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow186(code,U32.is_lt(code,2786))
    case False{}: propertiesBelow190(code,U32.is_lt(code,2817))
def propertiesBelow192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow193(code,U32.is_lt(code,2885))
def propertiesBelow195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow192(code,U32.is_lt(code,2879))
    case False{}: propertiesBelow194(code,U32.is_lt(code,2881))
def propertiesBelow196(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow197(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow198(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow197(code,U32.is_lt(code,2914))
def propertiesBelow199(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow196(code,U32.is_lt(code,2894))
    case False{}: propertiesBelow198(code,U32.is_lt(code,2903))
def propertiesBelow200(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow195(code,U32.is_lt(code,2880))
    case False{}: propertiesBelow199(code,U32.is_lt(code,2901))
def propertiesBelow201(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow191(code,U32.is_lt(code,2810))
    case False{}: propertiesBelow200(code,U32.is_lt(code,2893))
def propertiesBelow202(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow203(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow204(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow202(code,U32.is_lt(code,2946))
    case False{}: propertiesBelow203(code,U32.is_lt(code,3008))
def propertiesBelow205(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow206(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow207(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow206(code,U32.is_lt(code,3073))
def propertiesBelow208(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow205(code,U32.is_lt(code,3021))
    case False{}: propertiesBelow207(code,U32.is_lt(code,3072))
def propertiesBelow209(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow204(code,U32.is_lt(code,2947))
    case False{}: propertiesBelow208(code,U32.is_lt(code,3022))
def propertiesBelow210(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow211(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow212(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow211(code,U32.is_lt(code,3134))
def propertiesBelow213(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow210(code,U32.is_lt(code,3077))
    case False{}: propertiesBelow212(code,U32.is_lt(code,3133))
def propertiesBelow214(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow215(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow216(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow215(code,U32.is_lt(code,3150))
def propertiesBelow217(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow214(code,U32.is_lt(code,3142))
    case False{}: propertiesBelow216(code,U32.is_lt(code,3146))
def propertiesBelow218(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow213(code,U32.is_lt(code,3132))
    case False{}: propertiesBelow217(code,U32.is_lt(code,3145))
def propertiesBelow219(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow209(code,U32.is_lt(code,3009))
    case False{}: propertiesBelow218(code,U32.is_lt(code,3137))
def propertiesBelow220(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow201(code,U32.is_lt(code,2877))
    case False{}: propertiesBelow219(code,U32.is_lt(code,3076))
def propertiesBelow221(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow183(code,U32.is_lt(code,2627))
    case False{}: propertiesBelow220(code,U32.is_lt(code,2916))
def propertiesBelow222(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow223(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow224(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow222(code,U32.is_lt(code,3159))
    case False{}: propertiesBelow223(code,U32.is_lt(code,3172))
def propertiesBelow225(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow226(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow227(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow226(code,U32.is_lt(code,3263))
def propertiesBelow228(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow225(code,U32.is_lt(code,3202))
    case False{}: propertiesBelow227(code,U32.is_lt(code,3261))
def propertiesBelow229(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow224(code,U32.is_lt(code,3170))
    case False{}: propertiesBelow228(code,U32.is_lt(code,3260))
def propertiesBelow230(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow231(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow232(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow230(code,U32.is_lt(code,3270))
    case False{}: propertiesBelow231(code,U32.is_lt(code,3276))
def propertiesBelow233(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow234(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow235(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow234(code,U32.is_lt(code,3330))
def propertiesBelow236(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow233(code,U32.is_lt(code,3298))
    case False{}: propertiesBelow235(code,U32.is_lt(code,3328))
def propertiesBelow237(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow232(code,U32.is_lt(code,3271))
    case False{}: propertiesBelow236(code,U32.is_lt(code,3300))
def propertiesBelow238(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow229(code,U32.is_lt(code,3201))
    case False{}: propertiesBelow237(code,U32.is_lt(code,3278))
def propertiesBelow239(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow240(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow241(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow239(code,U32.is_lt(code,3389))
    case False{}: propertiesBelow240(code,U32.is_lt(code,3397))
def propertiesBelow242(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow243(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow244(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow243(code,U32.is_lt(code,3457))
def propertiesBelow245(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow242(code,U32.is_lt(code,3406))
    case False{}: propertiesBelow244(code,U32.is_lt(code,3428))
def propertiesBelow246(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow241(code,U32.is_lt(code,3393))
    case False{}: propertiesBelow245(code,U32.is_lt(code,3426))
def propertiesBelow247(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow248(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow249(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow248(code,U32.is_lt(code,3541))
def propertiesBelow250(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow247(code,U32.is_lt(code,3530))
    case False{}: propertiesBelow249(code,U32.is_lt(code,3538))
def propertiesBelow251(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow252(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow253(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow252(code,U32.is_lt(code,3636))
def propertiesBelow254(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow251(code,U32.is_lt(code,3543))
    case False{}: propertiesBelow253(code,U32.is_lt(code,3634))
def propertiesBelow255(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow250(code,U32.is_lt(code,3531))
    case False{}: propertiesBelow254(code,U32.is_lt(code,3633))
def propertiesBelow256(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow246(code,U32.is_lt(code,3405))
    case False{}: propertiesBelow255(code,U32.is_lt(code,3542))
def propertiesBelow257(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow238(code,U32.is_lt(code,3264))
    case False{}: propertiesBelow256(code,U32.is_lt(code,3458))
def propertiesBelow258(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow259(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow260(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow258(code,U32.is_lt(code,3654))
    case False{}: propertiesBelow259(code,U32.is_lt(code,3761))
def propertiesBelow261(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow262(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow263(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow262(code,U32.is_lt(code,3783))
def propertiesBelow264(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow261(code,U32.is_lt(code,3764))
    case False{}: propertiesBelow263(code,U32.is_lt(code,3782))
def propertiesBelow265(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow260(code,U32.is_lt(code,3663))
    case False{}: propertiesBelow264(code,U32.is_lt(code,3773))
def propertiesBelow266(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow267(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow268(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow267(code,U32.is_lt(code,3893))
def propertiesBelow269(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow266(code,U32.is_lt(code,3791))
    case False{}: propertiesBelow268(code,U32.is_lt(code,3866))
def propertiesBelow270(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow271(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow272(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow271(code,U32.is_lt(code,3898))
def propertiesBelow273(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow270(code,U32.is_lt(code,3895))
    case False{}: propertiesBelow272(code,U32.is_lt(code,3897))
def propertiesBelow274(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow269(code,U32.is_lt(code,3864))
    case False{}: propertiesBelow273(code,U32.is_lt(code,3896))
def propertiesBelow275(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow265(code,U32.is_lt(code,3762))
    case False{}: propertiesBelow274(code,U32.is_lt(code,3894))
def propertiesBelow276(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow277(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow278(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow276(code,U32.is_lt(code,3967))
    case False{}: propertiesBelow277(code,U32.is_lt(code,3973))
def propertiesBelow279(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow280(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow281(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow280(code,U32.is_lt(code,3993))
def propertiesBelow282(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow279(code,U32.is_lt(code,3976))
    case False{}: propertiesBelow281(code,U32.is_lt(code,3992))
def propertiesBelow283(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow278(code,U32.is_lt(code,3968))
    case False{}: propertiesBelow282(code,U32.is_lt(code,3981))
def propertiesBelow284(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow285(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow286(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow285(code,U32.is_lt(code,4145))
def propertiesBelow287(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow284(code,U32.is_lt(code,4038))
    case False{}: propertiesBelow286(code,U32.is_lt(code,4141))
def propertiesBelow288(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow289(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow290(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow289(code,U32.is_lt(code,4157))
def propertiesBelow291(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow288(code,U32.is_lt(code,4152))
    case False{}: propertiesBelow290(code,U32.is_lt(code,4155))
def propertiesBelow292(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow287(code,U32.is_lt(code,4039))
    case False{}: propertiesBelow291(code,U32.is_lt(code,4153))
def propertiesBelow293(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow283(code,U32.is_lt(code,3974))
    case False{}: propertiesBelow292(code,U32.is_lt(code,4146))
def propertiesBelow294(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow275(code,U32.is_lt(code,3784))
    case False{}: propertiesBelow293(code,U32.is_lt(code,4029))
def propertiesBelow295(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow257(code,U32.is_lt(code,3387))
    case False{}: propertiesBelow294(code,U32.is_lt(code,3953))
def propertiesBelow296(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow221(code,U32.is_lt(code,2765))
    case False{}: propertiesBelow295(code,U32.is_lt(code,3643))
def propertiesBelow297(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow147(code,U32.is_lt(code,1367))
    case False{}: propertiesBelow296(code,U32.is_lt(code,3157))
def propertiesBelow298(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow299(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow300(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow298(code,U32.is_lt(code,4184))
    case False{}: propertiesBelow299(code,U32.is_lt(code,4190))
def propertiesBelow301(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow302(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow303(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow302(code,U32.is_lt(code,4227))
def propertiesBelow304(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow301(code,U32.is_lt(code,4209))
    case False{}: propertiesBelow303(code,U32.is_lt(code,4226))
def propertiesBelow305(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow300(code,U32.is_lt(code,4186))
    case False{}: propertiesBelow304(code,U32.is_lt(code,4213))
def propertiesBelow306(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow307(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow308(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow306(code,U32.is_lt(code,4231))
    case False{}: propertiesBelow307(code,U32.is_lt(code,4238))
def propertiesBelow309(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow310(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow311(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow310(code,U32.is_lt(code,4295))
def propertiesBelow312(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow309(code,U32.is_lt(code,4254))
    case False{}: propertiesBelow311(code,U32.is_lt(code,4294))
def propertiesBelow313(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow308(code,U32.is_lt(code,4237))
    case False{}: propertiesBelow312(code,U32.is_lt(code,4256))
def propertiesBelow314(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow305(code,U32.is_lt(code,4193))
    case False{}: propertiesBelow313(code,U32.is_lt(code,4253))
def propertiesBelow315(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow316(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow317(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow315(code,U32.is_lt(code,4301))
    case False{}: propertiesBelow316(code,U32.is_lt(code,4304))
def propertiesBelow318(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 3
def propertiesBelow319(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow320(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow319(code,U32.is_lt(code,4957))
def propertiesBelow321(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow318(code,U32.is_lt(code,4348))
    case False{}: propertiesBelow320(code,U32.is_lt(code,4352))
def propertiesBelow322(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow317(code,U32.is_lt(code,4302))
    case False{}: propertiesBelow321(code,U32.is_lt(code,4349))
def propertiesBelow323(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow324(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow325(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow324(code,U32.is_lt(code,5118))
def propertiesBelow326(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow323(code,U32.is_lt(code,5024))
    case False{}: propertiesBelow325(code,U32.is_lt(code,5112))
def propertiesBelow327(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow328(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow329(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow328(code,U32.is_lt(code,5970))
def propertiesBelow330(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow327(code,U32.is_lt(code,5909))
    case False{}: propertiesBelow329(code,U32.is_lt(code,5940))
def propertiesBelow331(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow326(code,U32.is_lt(code,5110))
    case False{}: propertiesBelow330(code,U32.is_lt(code,5938))
def propertiesBelow332(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow322(code,U32.is_lt(code,4347))
    case False{}: propertiesBelow331(code,U32.is_lt(code,5906))
def propertiesBelow333(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow314(code,U32.is_lt(code,4229))
    case False{}: propertiesBelow332(code,U32.is_lt(code,4960))
def propertiesBelow334(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow335(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow336(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow334(code,U32.is_lt(code,6002))
    case False{}: propertiesBelow335(code,U32.is_lt(code,6068))
def propertiesBelow337(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow338(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow339(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow338(code,U32.is_lt(code,6087))
def propertiesBelow340(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow337(code,U32.is_lt(code,6071))
    case False{}: propertiesBelow339(code,U32.is_lt(code,6086))
def propertiesBelow341(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow336(code,U32.is_lt(code,6004))
    case False{}: propertiesBelow340(code,U32.is_lt(code,6078))
def propertiesBelow342(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow343(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow344(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow342(code,U32.is_lt(code,6100))
    case False{}: propertiesBelow343(code,U32.is_lt(code,6104))
def propertiesBelow345(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow346(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow347(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow346(code,U32.is_lt(code,6211))
def propertiesBelow348(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow345(code,U32.is_lt(code,6110))
    case False{}: propertiesBelow347(code,U32.is_lt(code,6160))
def propertiesBelow349(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow344(code,U32.is_lt(code,6103))
    case False{}: propertiesBelow348(code,U32.is_lt(code,6155))
def propertiesBelow350(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow341(code,U32.is_lt(code,6070))
    case False{}: propertiesBelow349(code,U32.is_lt(code,6109))
def propertiesBelow351(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow352(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow353(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow351(code,U32.is_lt(code,6277))
    case False{}: propertiesBelow352(code,U32.is_lt(code,6313))
def propertiesBelow354(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow355(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow356(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow355(code,U32.is_lt(code,6441))
def propertiesBelow357(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow354(code,U32.is_lt(code,6432))
    case False{}: propertiesBelow356(code,U32.is_lt(code,6439))
def propertiesBelow358(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow353(code,U32.is_lt(code,6279))
    case False{}: propertiesBelow357(code,U32.is_lt(code,6435))
def propertiesBelow359(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow360(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow361(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow360(code,U32.is_lt(code,6679))
def propertiesBelow362(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow359(code,U32.is_lt(code,6451))
    case False{}: propertiesBelow361(code,U32.is_lt(code,6460))
def propertiesBelow363(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow364(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow365(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow364(code,U32.is_lt(code,6743))
def propertiesBelow366(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow363(code,U32.is_lt(code,6683))
    case False{}: propertiesBelow365(code,U32.is_lt(code,6742))
def propertiesBelow367(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow362(code,U32.is_lt(code,6457))
    case False{}: propertiesBelow366(code,U32.is_lt(code,6684))
def propertiesBelow368(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow358(code,U32.is_lt(code,6314))
    case False{}: propertiesBelow367(code,U32.is_lt(code,6681))
def propertiesBelow369(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow350(code,U32.is_lt(code,6089))
    case False{}: propertiesBelow368(code,U32.is_lt(code,6450))
def propertiesBelow370(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow333(code,U32.is_lt(code,4296))
    case False{}: propertiesBelow369(code,U32.is_lt(code,6212))
def propertiesBelow371(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow372(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow373(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow371(code,U32.is_lt(code,6751))
    case False{}: propertiesBelow372(code,U32.is_lt(code,6753))
def propertiesBelow374(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow375(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow376(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow375(code,U32.is_lt(code,6771))
def propertiesBelow377(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow374(code,U32.is_lt(code,6755))
    case False{}: propertiesBelow376(code,U32.is_lt(code,6765))
def propertiesBelow378(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow373(code,U32.is_lt(code,6752))
    case False{}: propertiesBelow377(code,U32.is_lt(code,6757))
def propertiesBelow379(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow380(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow381(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow379(code,U32.is_lt(code,6783))
    case False{}: propertiesBelow380(code,U32.is_lt(code,6823))
def propertiesBelow382(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow383(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow384(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow383(code,U32.is_lt(code,6892))
def propertiesBelow385(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow382(code,U32.is_lt(code,6832))
    case False{}: propertiesBelow384(code,U32.is_lt(code,6880))
def propertiesBelow386(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow381(code,U32.is_lt(code,6784))
    case False{}: propertiesBelow385(code,U32.is_lt(code,6878))
def propertiesBelow387(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow378(code,U32.is_lt(code,6754))
    case False{}: propertiesBelow386(code,U32.is_lt(code,6824))
def propertiesBelow388(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow389(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow390(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow388(code,U32.is_lt(code,6916))
    case False{}: propertiesBelow389(code,U32.is_lt(code,6965))
def propertiesBelow391(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow392(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow393(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow392(code,U32.is_lt(code,6978))
def propertiesBelow394(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow391(code,U32.is_lt(code,6971))
    case False{}: propertiesBelow393(code,U32.is_lt(code,6973))
def propertiesBelow395(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow390(code,U32.is_lt(code,6964))
    case False{}: propertiesBelow394(code,U32.is_lt(code,6972))
def propertiesBelow396(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow397(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow398(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow397(code,U32.is_lt(code,7042))
def propertiesBelow399(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow396(code,U32.is_lt(code,7019))
    case False{}: propertiesBelow398(code,U32.is_lt(code,7040))
def propertiesBelow400(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow401(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow402(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow401(code,U32.is_lt(code,7083))
def propertiesBelow403(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow400(code,U32.is_lt(code,7078))
    case False{}: propertiesBelow402(code,U32.is_lt(code,7082))
def propertiesBelow404(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow399(code,U32.is_lt(code,7028))
    case False{}: propertiesBelow403(code,U32.is_lt(code,7080))
def propertiesBelow405(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow395(code,U32.is_lt(code,6966))
    case False{}: propertiesBelow404(code,U32.is_lt(code,7074))
def propertiesBelow406(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow387(code,U32.is_lt(code,6781))
    case False{}: propertiesBelow405(code,U32.is_lt(code,6979))
def propertiesBelow407(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow408(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow409(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow407(code,U32.is_lt(code,7142))
    case False{}: propertiesBelow408(code,U32.is_lt(code,7144))
def propertiesBelow410(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow411(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow412(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow411(code,U32.is_lt(code,7154))
def propertiesBelow413(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow410(code,U32.is_lt(code,7149))
    case False{}: propertiesBelow412(code,U32.is_lt(code,7151))
def propertiesBelow414(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow409(code,U32.is_lt(code,7143))
    case False{}: propertiesBelow413(code,U32.is_lt(code,7150))
def propertiesBelow415(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow416(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow417(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow416(code,U32.is_lt(code,7288))
def propertiesBelow418(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow415(code,U32.is_lt(code,7220))
    case False{}: propertiesBelow417(code,U32.is_lt(code,7224))
def propertiesBelow419(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow420(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow421(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow420(code,U32.is_lt(code,7355))
def propertiesBelow422(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow419(code,U32.is_lt(code,7296))
    case False{}: propertiesBelow421(code,U32.is_lt(code,7312))
def propertiesBelow423(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow418(code,U32.is_lt(code,7222))
    case False{}: propertiesBelow422(code,U32.is_lt(code,7307))
def propertiesBelow424(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow414(code,U32.is_lt(code,7146))
    case False{}: propertiesBelow423(code,U32.is_lt(code,7294))
def propertiesBelow425(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow426(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow427(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow425(code,U32.is_lt(code,7360))
    case False{}: propertiesBelow426(code,U32.is_lt(code,7379))
def propertiesBelow428(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow429(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow430(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow429(code,U32.is_lt(code,7405))
def propertiesBelow431(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow428(code,U32.is_lt(code,7393))
    case False{}: propertiesBelow430(code,U32.is_lt(code,7401))
def propertiesBelow432(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow427(code,U32.is_lt(code,7376))
    case False{}: propertiesBelow431(code,U32.is_lt(code,7394))
def propertiesBelow433(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow434(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow435(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow434(code,U32.is_lt(code,7418))
def propertiesBelow436(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow433(code,U32.is_lt(code,7412))
    case False{}: propertiesBelow435(code,U32.is_lt(code,7416))
def propertiesBelow437(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 3
def propertiesBelow438(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow439(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow438(code,U32.is_lt(code,7545))
def propertiesBelow440(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow437(code,U32.is_lt(code,7468))
    case False{}: propertiesBelow439(code,U32.is_lt(code,7544))
def propertiesBelow441(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow436(code,U32.is_lt(code,7413))
    case False{}: propertiesBelow440(code,U32.is_lt(code,7531))
def propertiesBelow442(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow432(code,U32.is_lt(code,7380))
    case False{}: propertiesBelow441(code,U32.is_lt(code,7424))
def propertiesBelow443(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow424(code,U32.is_lt(code,7212))
    case False{}: propertiesBelow442(code,U32.is_lt(code,7406))
def propertiesBelow444(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow406(code,U32.is_lt(code,6912))
    case False{}: propertiesBelow443(code,U32.is_lt(code,7357))
def propertiesBelow445(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow370(code,U32.is_lt(code,5972))
    case False{}: propertiesBelow444(code,U32.is_lt(code,7086))
def propertiesBelow446(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 2
def propertiesBelow447(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow448(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow446(code,U32.is_lt(code,7616))
    case False{}: propertiesBelow447(code,U32.is_lt(code,7958))
def propertiesBelow449(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow450(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow451(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow450(code,U32.is_lt(code,8008))
def propertiesBelow452(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow449(code,U32.is_lt(code,7966))
    case False{}: propertiesBelow451(code,U32.is_lt(code,8006))
def propertiesBelow453(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow448(code,U32.is_lt(code,7680))
    case False{}: propertiesBelow452(code,U32.is_lt(code,7968))
def propertiesBelow454(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow455(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow456(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow454(code,U32.is_lt(code,8016))
    case False{}: propertiesBelow455(code,U32.is_lt(code,8025))
def propertiesBelow457(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow458(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow459(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow458(code,U32.is_lt(code,8030))
def propertiesBelow460(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow457(code,U32.is_lt(code,8027))
    case False{}: propertiesBelow459(code,U32.is_lt(code,8029))
def propertiesBelow461(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow456(code,U32.is_lt(code,8024))
    case False{}: propertiesBelow460(code,U32.is_lt(code,8028))
def propertiesBelow462(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow453(code,U32.is_lt(code,7960))
    case False{}: propertiesBelow461(code,U32.is_lt(code,8026))
def propertiesBelow463(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow464(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow465(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow463(code,U32.is_lt(code,8062))
    case False{}: propertiesBelow464(code,U32.is_lt(code,8117))
def propertiesBelow466(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 2
def propertiesBelow467(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow468(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow467(code,U32.is_lt(code,8130))
def propertiesBelow469(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow466(code,U32.is_lt(code,8125))
    case False{}: propertiesBelow468(code,U32.is_lt(code,8127))
def propertiesBelow470(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow465(code,U32.is_lt(code,8064))
    case False{}: propertiesBelow469(code,U32.is_lt(code,8126))
def propertiesBelow471(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow472(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow473(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow472(code,U32.is_lt(code,8148))
def propertiesBelow474(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow471(code,U32.is_lt(code,8134))
    case False{}: propertiesBelow473(code,U32.is_lt(code,8144))
def propertiesBelow475(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow476(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 2
def propertiesBelow477(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow476(code,U32.is_lt(code,8173))
def propertiesBelow478(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow475(code,U32.is_lt(code,8156))
    case False{}: propertiesBelow477(code,U32.is_lt(code,8160))
def propertiesBelow479(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow474(code,U32.is_lt(code,8141))
    case False{}: propertiesBelow478(code,U32.is_lt(code,8157))
def propertiesBelow480(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow470(code,U32.is_lt(code,8118))
    case False{}: propertiesBelow479(code,U32.is_lt(code,8150))
def propertiesBelow481(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow462(code,U32.is_lt(code,8014))
    case False{}: propertiesBelow480(code,U32.is_lt(code,8133))
def propertiesBelow482(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow483(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow484(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow482(code,U32.is_lt(code,8178))
    case False{}: propertiesBelow483(code,U32.is_lt(code,8182))
def propertiesBelow485(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow486(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow487(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow486(code,U32.is_lt(code,8216))
def propertiesBelow488(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow485(code,U32.is_lt(code,8191))
    case False{}: propertiesBelow487(code,U32.is_lt(code,8208))
def propertiesBelow489(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow484(code,U32.is_lt(code,8181))
    case False{}: propertiesBelow488(code,U32.is_lt(code,8203))
def propertiesBelow490(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow491(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow492(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow491(code,U32.is_lt(code,8232))
def propertiesBelow493(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow490(code,U32.is_lt(code,8228))
    case False{}: propertiesBelow492(code,U32.is_lt(code,8231))
def propertiesBelow494(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow495(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow496(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow495(code,U32.is_lt(code,8294))
def propertiesBelow497(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow494(code,U32.is_lt(code,8239))
    case False{}: propertiesBelow496(code,U32.is_lt(code,8293))
def propertiesBelow498(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow493(code,U32.is_lt(code,8229))
    case False{}: propertiesBelow497(code,U32.is_lt(code,8288))
def propertiesBelow499(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow489(code,U32.is_lt(code,8189))
    case False{}: propertiesBelow498(code,U32.is_lt(code,8234))
def propertiesBelow500(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 3
def propertiesBelow501(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 3
def propertiesBelow502(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow500(code,U32.is_lt(code,8305))
    case False{}: propertiesBelow501(code,U32.is_lt(code,8319))
def propertiesBelow503(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 3
def propertiesBelow504(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow505(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow504(code,U32.is_lt(code,8433))
def propertiesBelow506(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow503(code,U32.is_lt(code,8336))
    case False{}: propertiesBelow505(code,U32.is_lt(code,8400))
def propertiesBelow507(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow502(code,U32.is_lt(code,8306))
    case False{}: propertiesBelow506(code,U32.is_lt(code,8349))
def propertiesBelow508(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow509(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow510(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow509(code,U32.is_lt(code,8458))
def propertiesBelow511(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow508(code,U32.is_lt(code,8451))
    case False{}: propertiesBelow510(code,U32.is_lt(code,8456))
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
    case False{}: propertiesBelow513(code,U32.is_lt(code,8478))
def propertiesBelow515(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow512(code,U32.is_lt(code,8469))
    case False{}: propertiesBelow514(code,U32.is_lt(code,8473))
def propertiesBelow516(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow511(code,U32.is_lt(code,8455))
    case False{}: propertiesBelow515(code,U32.is_lt(code,8470))
def propertiesBelow517(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow507(code,U32.is_lt(code,8320))
    case False{}: propertiesBelow516(code,U32.is_lt(code,8468))
def propertiesBelow518(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow499(code,U32.is_lt(code,8218))
    case False{}: propertiesBelow517(code,U32.is_lt(code,8450))
def propertiesBelow519(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow481(code,U32.is_lt(code,8031))
    case False{}: propertiesBelow518(code,U32.is_lt(code,8304))
def propertiesBelow520(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow521(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow522(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow520(code,U32.is_lt(code,8485))
    case False{}: propertiesBelow521(code,U32.is_lt(code,8487))
def propertiesBelow523(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow524(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow525(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow524(code,U32.is_lt(code,8495))
def propertiesBelow526(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow523(code,U32.is_lt(code,8489))
    case False{}: propertiesBelow525(code,U32.is_lt(code,8494))
def propertiesBelow527(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow522(code,U32.is_lt(code,8486))
    case False{}: propertiesBelow526(code,U32.is_lt(code,8490))
def propertiesBelow528(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow529(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow530(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow528(code,U32.is_lt(code,8505))
    case False{}: propertiesBelow529(code,U32.is_lt(code,8508))
def propertiesBelow531(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow532(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow533(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow532(code,U32.is_lt(code,8527))
def propertiesBelow534(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow531(code,U32.is_lt(code,8517))
    case False{}: propertiesBelow533(code,U32.is_lt(code,8526))
def propertiesBelow535(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow530(code,U32.is_lt(code,8506))
    case False{}: propertiesBelow534(code,U32.is_lt(code,8522))
def propertiesBelow536(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow527(code,U32.is_lt(code,8488))
    case False{}: propertiesBelow535(code,U32.is_lt(code,8512))
def propertiesBelow537(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow538(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow539(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow537(code,U32.is_lt(code,8576))
    case False{}: propertiesBelow538(code,U32.is_lt(code,8581))
def propertiesBelow540(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow541(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow542(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow541(code,U32.is_lt(code,11390))
def propertiesBelow543(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow540(code,U32.is_lt(code,9450))
    case False{}: propertiesBelow542(code,U32.is_lt(code,11388))
def propertiesBelow544(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow539(code,U32.is_lt(code,8579))
    case False{}: propertiesBelow543(code,U32.is_lt(code,11264))
def propertiesBelow545(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow546(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow547(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow546(code,U32.is_lt(code,11508))
def propertiesBelow548(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow545(code,U32.is_lt(code,11499))
    case False{}: propertiesBelow547(code,U32.is_lt(code,11506))
def propertiesBelow549(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow550(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow551(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow550(code,U32.is_lt(code,11565))
def propertiesBelow552(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow549(code,U32.is_lt(code,11558))
    case False{}: propertiesBelow551(code,U32.is_lt(code,11560))
def propertiesBelow553(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow548(code,U32.is_lt(code,11503))
    case False{}: propertiesBelow552(code,U32.is_lt(code,11559))
def propertiesBelow554(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow544(code,U32.is_lt(code,9398))
    case False{}: propertiesBelow553(code,U32.is_lt(code,11520))
def propertiesBelow555(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow536(code,U32.is_lt(code,8501))
    case False{}: propertiesBelow554(code,U32.is_lt(code,11493))
def propertiesBelow556(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow557(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow558(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow556(code,U32.is_lt(code,11631))
    case False{}: propertiesBelow557(code,U32.is_lt(code,11647))
def propertiesBelow559(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow560(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow561(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow560(code,U32.is_lt(code,11824))
def propertiesBelow562(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow559(code,U32.is_lt(code,11744))
    case False{}: propertiesBelow561(code,U32.is_lt(code,11823))
def propertiesBelow563(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow558(code,U32.is_lt(code,11632))
    case False{}: propertiesBelow562(code,U32.is_lt(code,11776))
def propertiesBelow564(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow565(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow566(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow565(code,U32.is_lt(code,12337))
def propertiesBelow567(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow564(code,U32.is_lt(code,12294))
    case False{}: propertiesBelow566(code,U32.is_lt(code,12334))
def propertiesBelow568(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow569(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow570(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow569(code,U32.is_lt(code,12447))
def propertiesBelow571(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow568(code,U32.is_lt(code,12347))
    case False{}: propertiesBelow570(code,U32.is_lt(code,12441))
def propertiesBelow572(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow567(code,U32.is_lt(code,12330))
    case False{}: propertiesBelow571(code,U32.is_lt(code,12348))
def propertiesBelow573(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow563(code,U32.is_lt(code,11648))
    case False{}: propertiesBelow572(code,U32.is_lt(code,12342))
def propertiesBelow574(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow575(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow576(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow574(code,U32.is_lt(code,12543))
    case False{}: propertiesBelow575(code,U32.is_lt(code,40982))
def propertiesBelow577(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow578(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow579(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow578(code,U32.is_lt(code,42560))
def propertiesBelow580(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow577(code,U32.is_lt(code,42238))
    case False{}: propertiesBelow579(code,U32.is_lt(code,42509))
def propertiesBelow581(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow576(code,U32.is_lt(code,40981))
    case False{}: propertiesBelow580(code,U32.is_lt(code,42508))
def propertiesBelow582(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow583(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow584(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow583(code,U32.is_lt(code,42622))
def propertiesBelow585(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow582(code,U32.is_lt(code,42607))
    case False{}: propertiesBelow584(code,U32.is_lt(code,42612))
def propertiesBelow586(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow587(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow588(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: propertiesBelow587(code,U32.is_lt(code,42656))
def propertiesBelow589(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow586(code,U32.is_lt(code,42624))
    case False{}: propertiesBelow588(code,U32.is_lt(code,42654))
def propertiesBelow590(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow585(code,U32.is_lt(code,42611))
    case False{}: propertiesBelow589(code,U32.is_lt(code,42652))
def propertiesBelow591(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow581(code,U32.is_lt(code,42232))
    case False{}: propertiesBelow590(code,U32.is_lt(code,42623))
def propertiesBelow592(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow573(code,U32.is_lt(code,12293))
    case False{}: propertiesBelow591(code,U32.is_lt(code,42606))
def propertiesBelow593(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow555(code,U32.is_lt(code,8544))
    case False{}: propertiesBelow592(code,U32.is_lt(code,12540))
def propertiesBelow594(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow519(code,U32.is_lt(code,8176))
    case False{}: propertiesBelow593(code,U32.is_lt(code,11566))
def propertiesBelow595(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow445(code,U32.is_lt(code,6744))
    case False{}: propertiesBelow594(code,U32.is_lt(code,8484))
def propertiesBelow596(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow297(code,U32.is_lt(code,2418))
    case False{}: propertiesBelow595(code,U32.is_lt(code,7579))
def propertiesBelow597(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow598(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def propertiesBelow599(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow597(code,U32.is_lt(code,42738))
    case False{}: propertiesBelow598(code,U32.is_lt(code,42786))
def propertiesBelow600(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow601(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow602(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow601(code,U32.is_lt(code,42895))
def propertiesBelow603(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow600(code,U32.is_lt(code,42865))
    case False{}: propertiesBelow602(code,U32.is_lt(code,42891))
def propertiesBelow604(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow599(code,U32.is_lt(code,42752))
    case False{}: propertiesBelow603(code,U32.is_lt(code,42888))
def propertiesBelow605(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow606(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow607(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow605(code,U32.is_lt(code,42973))
    case False{}: propertiesBelow606(code,U32.is_lt(code,42997))
def propertiesBelow608(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 3
def propertiesBelow609(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow610(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow609(code,U32.is_lt(code,43010))
def propertiesBelow611(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow608(code,U32.is_lt(code,43000))
    case False{}: propertiesBelow610(code,U32.is_lt(code,43003))
def propertiesBelow612(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow607(code,U32.is_lt(code,42993))
    case False{}: propertiesBelow611(code,U32.is_lt(code,43002))
def propertiesBelow613(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow604(code,U32.is_lt(code,42864))
    case False{}: propertiesBelow612(code,U32.is_lt(code,42999))
def propertiesBelow614(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow615(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow616(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow614(code,U32.is_lt(code,43014))
    case False{}: propertiesBelow615(code,U32.is_lt(code,43019))
def propertiesBelow617(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow618(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow619(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow618(code,U32.is_lt(code,43053))
def propertiesBelow620(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow617(code,U32.is_lt(code,43045))
    case False{}: propertiesBelow619(code,U32.is_lt(code,43052))
def propertiesBelow621(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow616(code,U32.is_lt(code,43015))
    case False{}: propertiesBelow620(code,U32.is_lt(code,43047))
def propertiesBelow622(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow623(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow624(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow623(code,U32.is_lt(code,43263))
def propertiesBelow625(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow622(code,U32.is_lt(code,43206))
    case False{}: propertiesBelow624(code,U32.is_lt(code,43250))
def propertiesBelow626(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow627(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow628(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow627(code,U32.is_lt(code,43346))
def propertiesBelow629(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow626(code,U32.is_lt(code,43302))
    case False{}: propertiesBelow628(code,U32.is_lt(code,43335))
def propertiesBelow630(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow625(code,U32.is_lt(code,43232))
    case False{}: propertiesBelow629(code,U32.is_lt(code,43310))
def propertiesBelow631(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow621(code,U32.is_lt(code,43020))
    case False{}: propertiesBelow630(code,U32.is_lt(code,43264))
def propertiesBelow632(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow613(code,U32.is_lt(code,42896))
    case False{}: propertiesBelow631(code,U32.is_lt(code,43204))
def propertiesBelow633(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow634(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow635(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow633(code,U32.is_lt(code,43395))
    case False{}: propertiesBelow634(code,U32.is_lt(code,43444))
def propertiesBelow636(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow637(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow638(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow637(code,U32.is_lt(code,43471))
def propertiesBelow639(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow636(code,U32.is_lt(code,43450))
    case False{}: propertiesBelow638(code,U32.is_lt(code,43454))
def propertiesBelow640(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow635(code,U32.is_lt(code,43443))
    case False{}: propertiesBelow639(code,U32.is_lt(code,43452))
def propertiesBelow641(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow642(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow643(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow641(code,U32.is_lt(code,43493))
    case False{}: propertiesBelow642(code,U32.is_lt(code,43561))
def propertiesBelow644(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow645(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow646(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow645(code,U32.is_lt(code,43575))
def propertiesBelow647(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow644(code,U32.is_lt(code,43569))
    case False{}: propertiesBelow646(code,U32.is_lt(code,43573))
def propertiesBelow648(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow643(code,U32.is_lt(code,43495))
    case False{}: propertiesBelow647(code,U32.is_lt(code,43571))
def propertiesBelow649(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow640(code,U32.is_lt(code,43446))
    case False{}: propertiesBelow648(code,U32.is_lt(code,43567))
def propertiesBelow650(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow651(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow652(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow650(code,U32.is_lt(code,43588))
    case False{}: propertiesBelow651(code,U32.is_lt(code,43597))
def propertiesBelow653(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow654(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow655(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow654(code,U32.is_lt(code,43696))
def propertiesBelow656(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow653(code,U32.is_lt(code,43633))
    case False{}: propertiesBelow655(code,U32.is_lt(code,43645))
def propertiesBelow657(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow652(code,U32.is_lt(code,43596))
    case False{}: propertiesBelow656(code,U32.is_lt(code,43644))
def propertiesBelow658(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow659(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow660(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow659(code,U32.is_lt(code,43705))
def propertiesBelow661(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow658(code,U32.is_lt(code,43698))
    case False{}: propertiesBelow660(code,U32.is_lt(code,43703))
def propertiesBelow662(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow663(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow664(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow663(code,U32.is_lt(code,43741))
def propertiesBelow665(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow662(code,U32.is_lt(code,43712))
    case False{}: propertiesBelow664(code,U32.is_lt(code,43714))
def propertiesBelow666(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow661(code,U32.is_lt(code,43701))
    case False{}: propertiesBelow665(code,U32.is_lt(code,43713))
def propertiesBelow667(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow657(code,U32.is_lt(code,43632))
    case False{}: propertiesBelow666(code,U32.is_lt(code,43710))
def propertiesBelow668(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow649(code,U32.is_lt(code,43472))
    case False{}: propertiesBelow667(code,U32.is_lt(code,43697))
def propertiesBelow669(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow632(code,U32.is_lt(code,43011))
    case False{}: propertiesBelow668(code,U32.is_lt(code,43587))
def propertiesBelow670(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow671(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow672(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow670(code,U32.is_lt(code,43756))
    case False{}: propertiesBelow671(code,U32.is_lt(code,43763))
def propertiesBelow673(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow674(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 2
def propertiesBelow675(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow674(code,U32.is_lt(code,43867))
def propertiesBelow676(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow673(code,U32.is_lt(code,43766))
    case False{}: propertiesBelow675(code,U32.is_lt(code,43824))
def propertiesBelow677(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow672(code,U32.is_lt(code,43758))
    case False{}: propertiesBelow676(code,U32.is_lt(code,43767))
def propertiesBelow678(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow679(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 2
def propertiesBelow680(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow678(code,U32.is_lt(code,43872))
    case False{}: propertiesBelow679(code,U32.is_lt(code,43882))
def propertiesBelow681(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow682(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow683(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow682(code,U32.is_lt(code,44006))
def propertiesBelow684(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow681(code,U32.is_lt(code,43888))
    case False{}: propertiesBelow683(code,U32.is_lt(code,44005))
def propertiesBelow685(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow680(code,U32.is_lt(code,43881))
    case False{}: propertiesBelow684(code,U32.is_lt(code,43968))
def propertiesBelow686(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow677(code,U32.is_lt(code,43765))
    case False{}: propertiesBelow685(code,U32.is_lt(code,43884))
def propertiesBelow687(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow688(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow689(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow687(code,U32.is_lt(code,44009))
    case False{}: propertiesBelow688(code,U32.is_lt(code,44014))
def propertiesBelow690(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow691(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow692(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow691(code,U32.is_lt(code,64286))
def propertiesBelow693(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow690(code,U32.is_lt(code,64263))
    case False{}: propertiesBelow692(code,U32.is_lt(code,64280))
def propertiesBelow694(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow689(code,U32.is_lt(code,44013))
    case False{}: propertiesBelow693(code,U32.is_lt(code,64275))
def propertiesBelow695(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow696(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow697(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow696(code,U32.is_lt(code,65040))
def propertiesBelow698(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow695(code,U32.is_lt(code,64434))
    case False{}: propertiesBelow697(code,U32.is_lt(code,65024))
def propertiesBelow699(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow700(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow701(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow700(code,U32.is_lt(code,65106))
def propertiesBelow702(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow699(code,U32.is_lt(code,65044))
    case False{}: propertiesBelow701(code,U32.is_lt(code,65072))
def propertiesBelow703(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow698(code,U32.is_lt(code,64451))
    case False{}: propertiesBelow702(code,U32.is_lt(code,65056))
def propertiesBelow704(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow694(code,U32.is_lt(code,64256))
    case False{}: propertiesBelow703(code,U32.is_lt(code,65043))
def propertiesBelow705(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow686(code,U32.is_lt(code,43868))
    case False{}: propertiesBelow704(code,U32.is_lt(code,64287))
def propertiesBelow706(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow707(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow708(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow706(code,U32.is_lt(code,65109))
    case False{}: propertiesBelow707(code,U32.is_lt(code,65279))
def propertiesBelow709(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow710(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow711(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow710(code,U32.is_lt(code,65295))
def propertiesBelow712(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow709(code,U32.is_lt(code,65287))
    case False{}: propertiesBelow711(code,U32.is_lt(code,65294))
def propertiesBelow713(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow708(code,U32.is_lt(code,65110))
    case False{}: propertiesBelow712(code,U32.is_lt(code,65288))
def propertiesBelow714(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow715(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow716(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow715(code,U32.is_lt(code,65342))
def propertiesBelow717(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow714(code,U32.is_lt(code,65307))
    case False{}: propertiesBelow716(code,U32.is_lt(code,65339))
def propertiesBelow718(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow719(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow720(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow719(code,U32.is_lt(code,65392))
def propertiesBelow721(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow718(code,U32.is_lt(code,65344))
    case False{}: propertiesBelow720(code,U32.is_lt(code,65371))
def propertiesBelow722(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow717(code,U32.is_lt(code,65313))
    case False{}: propertiesBelow721(code,U32.is_lt(code,65345))
def propertiesBelow723(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow713(code,U32.is_lt(code,65280))
    case False{}: propertiesBelow722(code,U32.is_lt(code,65343))
def propertiesBelow724(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow725(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow726(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow724(code,U32.is_lt(code,65438))
    case False{}: propertiesBelow725(code,U32.is_lt(code,65507))
def propertiesBelow727(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow728(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow729(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow728(code,U32.is_lt(code,66046))
def propertiesBelow730(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow727(code,U32.is_lt(code,65529))
    case False{}: propertiesBelow729(code,U32.is_lt(code,66045))
def propertiesBelow731(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow726(code,U32.is_lt(code,65440))
    case False{}: propertiesBelow730(code,U32.is_lt(code,65532))
def propertiesBelow732(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow733(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow734(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow733(code,U32.is_lt(code,66560))
def propertiesBelow735(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow732(code,U32.is_lt(code,66273))
    case False{}: propertiesBelow734(code,U32.is_lt(code,66427))
def propertiesBelow736(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow737(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow738(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow737(code,U32.is_lt(code,66812))
def propertiesBelow739(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow736(code,U32.is_lt(code,66736))
    case False{}: propertiesBelow738(code,U32.is_lt(code,66776))
def propertiesBelow740(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow735(code,U32.is_lt(code,66422))
    case False{}: propertiesBelow739(code,U32.is_lt(code,66772))
def propertiesBelow741(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow731(code,U32.is_lt(code,65508))
    case False{}: propertiesBelow740(code,U32.is_lt(code,66640))
def propertiesBelow742(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow723(code,U32.is_lt(code,65306))
    case False{}: propertiesBelow741(code,U32.is_lt(code,66272))
def propertiesBelow743(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow705(code,U32.is_lt(code,44008))
    case False{}: propertiesBelow742(code,U32.is_lt(code,65393))
def propertiesBelow744(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow669(code,U32.is_lt(code,43392))
    case False{}: propertiesBelow743(code,U32.is_lt(code,65107))
def propertiesBelow745(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow746(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow747(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow745(code,U32.is_lt(code,66939))
    case False{}: propertiesBelow746(code,U32.is_lt(code,66955))
def propertiesBelow748(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow749(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow750(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow749(code,U32.is_lt(code,66967))
def propertiesBelow751(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow748(code,U32.is_lt(code,66963))
    case False{}: propertiesBelow750(code,U32.is_lt(code,66966))
def propertiesBelow752(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow747(code,U32.is_lt(code,66940))
    case False{}: propertiesBelow751(code,U32.is_lt(code,66964))
def propertiesBelow753(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow754(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow755(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow753(code,U32.is_lt(code,66979))
    case False{}: propertiesBelow754(code,U32.is_lt(code,66995))
def propertiesBelow756(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow757(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 2
def propertiesBelow758(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow757(code,U32.is_lt(code,67457))
def propertiesBelow759(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow756(code,U32.is_lt(code,67003))
    case False{}: propertiesBelow758(code,U32.is_lt(code,67456))
def propertiesBelow760(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow755(code,U32.is_lt(code,66994))
    case False{}: propertiesBelow759(code,U32.is_lt(code,67005))
def propertiesBelow761(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow752(code,U32.is_lt(code,66956))
    case False{}: propertiesBelow760(code,U32.is_lt(code,67002))
def propertiesBelow762(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 0
def propertiesBelow763(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 0
def propertiesBelow764(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow762(code,U32.is_lt(code,67462))
    case False{}: propertiesBelow763(code,U32.is_lt(code,67505))
def propertiesBelow765(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 0
def propertiesBelow766(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow767(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow766(code,U32.is_lt(code,68101))
def propertiesBelow768(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow765(code,U32.is_lt(code,67515))
    case False{}: propertiesBelow767(code,U32.is_lt(code,68100))
def propertiesBelow769(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow764(code,U32.is_lt(code,67463))
    case False{}: propertiesBelow768(code,U32.is_lt(code,68097))
def propertiesBelow770(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow771(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow772(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow771(code,U32.is_lt(code,68155))
def propertiesBelow773(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow770(code,U32.is_lt(code,68108))
    case False{}: propertiesBelow772(code,U32.is_lt(code,68152))
def propertiesBelow774(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow775(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow776(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow775(code,U32.is_lt(code,68736))
def propertiesBelow777(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow774(code,U32.is_lt(code,68160))
    case False{}: propertiesBelow776(code,U32.is_lt(code,68327))
def propertiesBelow778(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow773(code,U32.is_lt(code,68112))
    case False{}: propertiesBelow777(code,U32.is_lt(code,68325))
def propertiesBelow779(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow769(code,U32.is_lt(code,67506))
    case False{}: propertiesBelow778(code,U32.is_lt(code,68159))
def propertiesBelow780(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow761(code,U32.is_lt(code,66978))
    case False{}: propertiesBelow779(code,U32.is_lt(code,68103))
def propertiesBelow781(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow782(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow783(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow781(code,U32.is_lt(code,68800))
    case False{}: propertiesBelow782(code,U32.is_lt(code,68900))
def propertiesBelow784(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow785(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow786(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow785(code,U32.is_lt(code,68966))
def propertiesBelow787(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow784(code,U32.is_lt(code,68942))
    case False{}: propertiesBelow786(code,U32.is_lt(code,68944))
def propertiesBelow788(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow783(code,U32.is_lt(code,68851))
    case False{}: propertiesBelow787(code,U32.is_lt(code,68943))
def propertiesBelow789(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow790(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow791(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow790(code,U32.is_lt(code,68998))
def propertiesBelow792(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow789(code,U32.is_lt(code,68974))
    case False{}: propertiesBelow791(code,U32.is_lt(code,68976))
def propertiesBelow793(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow794(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow795(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow794(code,U32.is_lt(code,69370))
def propertiesBelow796(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow793(code,U32.is_lt(code,69293))
    case False{}: propertiesBelow795(code,U32.is_lt(code,69318))
def propertiesBelow797(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow792(code,U32.is_lt(code,68975))
    case False{}: propertiesBelow796(code,U32.is_lt(code,69317))
def propertiesBelow798(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow788(code,U32.is_lt(code,68904))
    case False{}: propertiesBelow797(code,U32.is_lt(code,69291))
def propertiesBelow799(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow800(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow801(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow799(code,U32.is_lt(code,69446))
    case False{}: propertiesBelow800(code,U32.is_lt(code,69506))
def propertiesBelow802(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow803(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow804(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow803(code,U32.is_lt(code,69703))
def propertiesBelow805(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow802(code,U32.is_lt(code,69633))
    case False{}: propertiesBelow804(code,U32.is_lt(code,69688))
def propertiesBelow806(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow801(code,U32.is_lt(code,69457))
    case False{}: propertiesBelow805(code,U32.is_lt(code,69634))
def propertiesBelow807(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow808(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow809(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow808(code,U32.is_lt(code,69759))
def propertiesBelow810(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow807(code,U32.is_lt(code,69745))
    case False{}: propertiesBelow809(code,U32.is_lt(code,69749))
def propertiesBelow811(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow812(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow813(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow812(code,U32.is_lt(code,69819))
def propertiesBelow814(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow811(code,U32.is_lt(code,69811))
    case False{}: propertiesBelow813(code,U32.is_lt(code,69817))
def propertiesBelow815(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow810(code,U32.is_lt(code,69747))
    case False{}: propertiesBelow814(code,U32.is_lt(code,69815))
def propertiesBelow816(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow806(code,U32.is_lt(code,69510))
    case False{}: propertiesBelow815(code,U32.is_lt(code,69762))
def propertiesBelow817(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow798(code,U32.is_lt(code,68969))
    case False{}: propertiesBelow816(code,U32.is_lt(code,69744))
def propertiesBelow818(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow780(code,U32.is_lt(code,67459))
    case False{}: propertiesBelow817(code,U32.is_lt(code,69376))
def propertiesBelow819(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow820(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow821(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow819(code,U32.is_lt(code,69822))
    case False{}: propertiesBelow820(code,U32.is_lt(code,69827))
def propertiesBelow822(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow823(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow824(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow823(code,U32.is_lt(code,69927))
def propertiesBelow825(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow822(code,U32.is_lt(code,69838))
    case False{}: propertiesBelow824(code,U32.is_lt(code,69891))
def propertiesBelow826(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow821(code,U32.is_lt(code,69826))
    case False{}: propertiesBelow825(code,U32.is_lt(code,69888))
def propertiesBelow827(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow828(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow829(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow827(code,U32.is_lt(code,69933))
    case False{}: propertiesBelow828(code,U32.is_lt(code,70003))
def propertiesBelow830(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow831(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow832(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow831(code,U32.is_lt(code,70079))
def propertiesBelow833(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow830(code,U32.is_lt(code,70016))
    case False{}: propertiesBelow832(code,U32.is_lt(code,70070))
def propertiesBelow834(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow829(code,U32.is_lt(code,69941))
    case False{}: propertiesBelow833(code,U32.is_lt(code,70018))
def propertiesBelow835(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow826(code,U32.is_lt(code,69837))
    case False{}: propertiesBelow834(code,U32.is_lt(code,70004))
def propertiesBelow836(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow837(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow838(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow836(code,U32.is_lt(code,70093))
    case False{}: propertiesBelow837(code,U32.is_lt(code,70096))
def propertiesBelow839(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow840(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow841(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow840(code,U32.is_lt(code,70198))
def propertiesBelow842(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow839(code,U32.is_lt(code,70194))
    case False{}: propertiesBelow841(code,U32.is_lt(code,70197))
def propertiesBelow843(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow838(code,U32.is_lt(code,70095))
    case False{}: propertiesBelow842(code,U32.is_lt(code,70196))
def propertiesBelow844(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow845(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow846(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow845(code,U32.is_lt(code,70210))
def propertiesBelow847(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow844(code,U32.is_lt(code,70206))
    case False{}: propertiesBelow846(code,U32.is_lt(code,70209))
def propertiesBelow848(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow849(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow850(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow849(code,U32.is_lt(code,70400))
def propertiesBelow851(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow848(code,U32.is_lt(code,70368))
    case False{}: propertiesBelow850(code,U32.is_lt(code,70379))
def propertiesBelow852(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow847(code,U32.is_lt(code,70207))
    case False{}: propertiesBelow851(code,U32.is_lt(code,70371))
def propertiesBelow853(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow843(code,U32.is_lt(code,70191))
    case False{}: propertiesBelow852(code,U32.is_lt(code,70367))
def propertiesBelow854(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow835(code,U32.is_lt(code,69932))
    case False{}: propertiesBelow853(code,U32.is_lt(code,70200))
def propertiesBelow855(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow856(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow857(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow855(code,U32.is_lt(code,70459))
    case False{}: propertiesBelow856(code,U32.is_lt(code,70464))
def propertiesBelow858(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow859(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow860(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow859(code,U32.is_lt(code,70517))
def propertiesBelow861(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow858(code,U32.is_lt(code,70502))
    case False{}: propertiesBelow860(code,U32.is_lt(code,70512))
def propertiesBelow862(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow857(code,U32.is_lt(code,70461))
    case False{}: propertiesBelow861(code,U32.is_lt(code,70509))
def propertiesBelow863(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow864(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow865(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow864(code,U32.is_lt(code,70608))
def propertiesBelow866(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow863(code,U32.is_lt(code,70593))
    case False{}: propertiesBelow865(code,U32.is_lt(code,70607))
def propertiesBelow867(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow868(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow869(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow868(code,U32.is_lt(code,70627))
def propertiesBelow870(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow867(code,U32.is_lt(code,70610))
    case False{}: propertiesBelow869(code,U32.is_lt(code,70625))
def propertiesBelow871(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow866(code,U32.is_lt(code,70606))
    case False{}: propertiesBelow870(code,U32.is_lt(code,70611))
def propertiesBelow872(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow862(code,U32.is_lt(code,70465))
    case False{}: propertiesBelow871(code,U32.is_lt(code,70609))
def propertiesBelow873(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow874(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow875(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow873(code,U32.is_lt(code,70720))
    case False{}: propertiesBelow874(code,U32.is_lt(code,70725))
def propertiesBelow876(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow877(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow878(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow877(code,U32.is_lt(code,70835))
def propertiesBelow879(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow876(code,U32.is_lt(code,70727))
    case False{}: propertiesBelow878(code,U32.is_lt(code,70751))
def propertiesBelow880(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow875(code,U32.is_lt(code,70722))
    case False{}: propertiesBelow879(code,U32.is_lt(code,70750))
def propertiesBelow881(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow882(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow883(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow882(code,U32.is_lt(code,70849))
def propertiesBelow884(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow881(code,U32.is_lt(code,70842))
    case False{}: propertiesBelow883(code,U32.is_lt(code,70847))
def propertiesBelow885(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow886(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow887(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow886(code,U32.is_lt(code,71100))
def propertiesBelow888(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow885(code,U32.is_lt(code,70852))
    case False{}: propertiesBelow887(code,U32.is_lt(code,71094))
def propertiesBelow889(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow884(code,U32.is_lt(code,70843))
    case False{}: propertiesBelow888(code,U32.is_lt(code,71090))
def propertiesBelow890(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow880(code,U32.is_lt(code,70726))
    case False{}: propertiesBelow889(code,U32.is_lt(code,70850))
def propertiesBelow891(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow872(code,U32.is_lt(code,70587))
    case False{}: propertiesBelow890(code,U32.is_lt(code,70841))
def propertiesBelow892(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow854(code,U32.is_lt(code,70089))
    case False{}: propertiesBelow891(code,U32.is_lt(code,70712))
def propertiesBelow893(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow818(code,U32.is_lt(code,68787))
    case False{}: propertiesBelow892(code,U32.is_lt(code,70402))
def propertiesBelow894(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow744(code,U32.is_lt(code,43742))
    case False{}: propertiesBelow893(code,U32.is_lt(code,69821))
def propertiesBelow895(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow896(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow897(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow895(code,U32.is_lt(code,71103))
    case False{}: propertiesBelow896(code,U32.is_lt(code,71132))
def propertiesBelow898(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow899(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow900(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow899(code,U32.is_lt(code,71230))
def propertiesBelow901(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow898(code,U32.is_lt(code,71219))
    case False{}: propertiesBelow900(code,U32.is_lt(code,71229))
def propertiesBelow902(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow897(code,U32.is_lt(code,71105))
    case False{}: propertiesBelow901(code,U32.is_lt(code,71227))
def propertiesBelow903(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow904(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow905(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow903(code,U32.is_lt(code,71233))
    case False{}: propertiesBelow904(code,U32.is_lt(code,71340))
def propertiesBelow906(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow907(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow908(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow907(code,U32.is_lt(code,71351))
def propertiesBelow909(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow906(code,U32.is_lt(code,71342))
    case False{}: propertiesBelow908(code,U32.is_lt(code,71350))
def propertiesBelow910(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow905(code,U32.is_lt(code,71339))
    case False{}: propertiesBelow909(code,U32.is_lt(code,71344))
def propertiesBelow911(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow902(code,U32.is_lt(code,71134))
    case False{}: propertiesBelow910(code,U32.is_lt(code,71341))
def propertiesBelow912(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow913(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow914(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow912(code,U32.is_lt(code,71453))
    case False{}: propertiesBelow913(code,U32.is_lt(code,71455))
def propertiesBelow915(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow916(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow917(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow916(code,U32.is_lt(code,71468))
def propertiesBelow918(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow915(code,U32.is_lt(code,71458))
    case False{}: propertiesBelow917(code,U32.is_lt(code,71463))
def propertiesBelow919(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow914(code,U32.is_lt(code,71454))
    case False{}: propertiesBelow918(code,U32.is_lt(code,71462))
def propertiesBelow920(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow921(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow922(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow921(code,U32.is_lt(code,71840))
def propertiesBelow923(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow920(code,U32.is_lt(code,71736))
    case False{}: propertiesBelow922(code,U32.is_lt(code,71739))
def propertiesBelow924(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow925(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow926(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow925(code,U32.is_lt(code,71999))
def propertiesBelow927(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow924(code,U32.is_lt(code,71995))
    case False{}: propertiesBelow926(code,U32.is_lt(code,71998))
def propertiesBelow928(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow923(code,U32.is_lt(code,71737))
    case False{}: propertiesBelow927(code,U32.is_lt(code,71997))
def propertiesBelow929(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow919(code,U32.is_lt(code,71456))
    case False{}: propertiesBelow928(code,U32.is_lt(code,71904))
def propertiesBelow930(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow911(code,U32.is_lt(code,71231))
    case False{}: propertiesBelow929(code,U32.is_lt(code,71727))
def propertiesBelow931(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow932(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow933(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow931(code,U32.is_lt(code,72004))
    case False{}: propertiesBelow932(code,U32.is_lt(code,72152))
def propertiesBelow934(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow935(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow936(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow935(code,U32.is_lt(code,72193))
def propertiesBelow937(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow934(code,U32.is_lt(code,72156))
    case False{}: propertiesBelow936(code,U32.is_lt(code,72161))
def propertiesBelow938(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow933(code,U32.is_lt(code,72148))
    case False{}: propertiesBelow937(code,U32.is_lt(code,72160))
def propertiesBelow939(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow940(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow941(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow940(code,U32.is_lt(code,72255))
def propertiesBelow942(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow939(code,U32.is_lt(code,72243))
    case False{}: propertiesBelow941(code,U32.is_lt(code,72251))
def propertiesBelow943(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow944(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow945(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow944(code,U32.is_lt(code,72281))
def propertiesBelow946(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow943(code,U32.is_lt(code,72264))
    case False{}: propertiesBelow945(code,U32.is_lt(code,72279))
def propertiesBelow947(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow942(code,U32.is_lt(code,72249))
    case False{}: propertiesBelow946(code,U32.is_lt(code,72273))
def propertiesBelow948(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow938(code,U32.is_lt(code,72154))
    case False{}: propertiesBelow947(code,U32.is_lt(code,72263))
def propertiesBelow949(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow950(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow951(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow949(code,U32.is_lt(code,72330))
    case False{}: propertiesBelow950(code,U32.is_lt(code,72344))
def propertiesBelow952(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow953(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow954(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow953(code,U32.is_lt(code,72549))
def propertiesBelow955(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow952(code,U32.is_lt(code,72544))
    case False{}: propertiesBelow954(code,U32.is_lt(code,72546))
def propertiesBelow956(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow951(code,U32.is_lt(code,72343))
    case False{}: propertiesBelow955(code,U32.is_lt(code,72545))
def propertiesBelow957(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow958(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow959(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow958(code,U32.is_lt(code,72760))
def propertiesBelow960(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow957(code,U32.is_lt(code,72551))
    case False{}: propertiesBelow959(code,U32.is_lt(code,72759))
def propertiesBelow961(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow962(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow963(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow962(code,U32.is_lt(code,72872))
def propertiesBelow964(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow961(code,U32.is_lt(code,72767))
    case False{}: propertiesBelow963(code,U32.is_lt(code,72850))
def propertiesBelow965(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow960(code,U32.is_lt(code,72752))
    case False{}: propertiesBelow964(code,U32.is_lt(code,72768))
def propertiesBelow966(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow956(code,U32.is_lt(code,72346))
    case False{}: propertiesBelow965(code,U32.is_lt(code,72766))
def propertiesBelow967(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow948(code,U32.is_lt(code,72203))
    case False{}: propertiesBelow966(code,U32.is_lt(code,72550))
def propertiesBelow968(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow930(code,U32.is_lt(code,71352))
    case False{}: propertiesBelow967(code,U32.is_lt(code,72284))
def propertiesBelow969(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow970(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow971(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow969(code,U32.is_lt(code,72881))
    case False{}: propertiesBelow970(code,U32.is_lt(code,72884))
def propertiesBelow972(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow973(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow974(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow973(code,U32.is_lt(code,73018))
def propertiesBelow975(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow972(code,U32.is_lt(code,72887))
    case False{}: propertiesBelow974(code,U32.is_lt(code,73015))
def propertiesBelow976(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow971(code,U32.is_lt(code,72882))
    case False{}: propertiesBelow975(code,U32.is_lt(code,73009))
def propertiesBelow977(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow978(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow979(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow977(code,U32.is_lt(code,73020))
    case False{}: propertiesBelow978(code,U32.is_lt(code,73023))
def propertiesBelow980(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow981(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow982(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow981(code,U32.is_lt(code,73106))
def propertiesBelow983(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow980(code,U32.is_lt(code,73031))
    case False{}: propertiesBelow982(code,U32.is_lt(code,73104))
def propertiesBelow984(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow979(code,U32.is_lt(code,73022))
    case False{}: propertiesBelow983(code,U32.is_lt(code,73032))
def propertiesBelow985(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow976(code,U32.is_lt(code,72885))
    case False{}: propertiesBelow984(code,U32.is_lt(code,73030))
def propertiesBelow986(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow987(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow988(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow986(code,U32.is_lt(code,73110))
    case False{}: propertiesBelow987(code,U32.is_lt(code,73112))
def propertiesBelow989(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow990(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow991(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow990(code,U32.is_lt(code,73472))
def propertiesBelow992(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow989(code,U32.is_lt(code,73178))
    case False{}: propertiesBelow991(code,U32.is_lt(code,73461))
def propertiesBelow993(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow988(code,U32.is_lt(code,73111))
    case False{}: propertiesBelow992(code,U32.is_lt(code,73459))
def propertiesBelow994(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow995(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow996(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow995(code,U32.is_lt(code,73537))
def propertiesBelow997(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow994(code,U32.is_lt(code,73526))
    case False{}: propertiesBelow996(code,U32.is_lt(code,73536))
def propertiesBelow998(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow999(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1000(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow999(code,U32.is_lt(code,78896))
def propertiesBelow1001(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow998(code,U32.is_lt(code,73539))
    case False{}: propertiesBelow1000(code,U32.is_lt(code,73563))
def propertiesBelow1002(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow997(code,U32.is_lt(code,73531))
    case False{}: propertiesBelow1001(code,U32.is_lt(code,73562))
def propertiesBelow1003(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow993(code,U32.is_lt(code,73177))
    case False{}: propertiesBelow1002(code,U32.is_lt(code,73538))
def propertiesBelow1004(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow985(code,U32.is_lt(code,73019))
    case False{}: propertiesBelow1003(code,U32.is_lt(code,73474))
def propertiesBelow1005(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1006(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1007(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1005(code,U32.is_lt(code,78919))
    case False{}: propertiesBelow1006(code,U32.is_lt(code,90398))
def propertiesBelow1008(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1009(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1010(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1009(code,U32.is_lt(code,92917))
def propertiesBelow1011(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1008(code,U32.is_lt(code,90413))
    case False{}: propertiesBelow1010(code,U32.is_lt(code,92912))
def propertiesBelow1012(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1007(code,U32.is_lt(code,78934))
    case False{}: propertiesBelow1011(code,U32.is_lt(code,90416))
def propertiesBelow1013(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1014(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1015(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1014(code,U32.is_lt(code,93504))
def propertiesBelow1016(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1013(code,U32.is_lt(code,92983))
    case False{}: propertiesBelow1015(code,U32.is_lt(code,92996))
def propertiesBelow1017(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1018(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1019(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1018(code,U32.is_lt(code,93824))
def propertiesBelow1020(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1017(code,U32.is_lt(code,93547))
    case False{}: propertiesBelow1019(code,U32.is_lt(code,93760))
def propertiesBelow1021(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1016(code,U32.is_lt(code,92992))
    case False{}: propertiesBelow1020(code,U32.is_lt(code,93549))
def propertiesBelow1022(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1012(code,U32.is_lt(code,90410))
    case False{}: propertiesBelow1021(code,U32.is_lt(code,93507))
def propertiesBelow1023(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1024(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1025(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1023(code,U32.is_lt(code,93881))
    case False{}: propertiesBelow1024(code,U32.is_lt(code,93908))
def propertiesBelow1026(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1027(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1028(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1027(code,U32.is_lt(code,94176))
def propertiesBelow1029(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1026(code,U32.is_lt(code,94032))
    case False{}: propertiesBelow1028(code,U32.is_lt(code,94112))
def propertiesBelow1030(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1025(code,U32.is_lt(code,93883))
    case False{}: propertiesBelow1029(code,U32.is_lt(code,94095))
def propertiesBelow1031(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1032(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1033(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1032(code,U32.is_lt(code,94196))
def propertiesBelow1034(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1031(code,U32.is_lt(code,94179))
    case False{}: propertiesBelow1033(code,U32.is_lt(code,94194))
def propertiesBelow1035(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1036(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1037(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1036(code,U32.is_lt(code,110589))
def propertiesBelow1038(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1035(code,U32.is_lt(code,110580))
    case False{}: propertiesBelow1037(code,U32.is_lt(code,110588))
def propertiesBelow1039(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1034(code,U32.is_lt(code,94181))
    case False{}: propertiesBelow1038(code,U32.is_lt(code,110581))
def propertiesBelow1040(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1030(code,U32.is_lt(code,94031))
    case False{}: propertiesBelow1039(code,U32.is_lt(code,110576))
def propertiesBelow1041(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1022(code,U32.is_lt(code,92976))
    case False{}: propertiesBelow1040(code,U32.is_lt(code,94178))
def propertiesBelow1042(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1004(code,U32.is_lt(code,73109))
    case False{}: propertiesBelow1041(code,U32.is_lt(code,93856))
def propertiesBelow1043(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow968(code,U32.is_lt(code,72003))
    case False{}: propertiesBelow1042(code,U32.is_lt(code,78913))
def propertiesBelow1044(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1045(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1046(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1044(code,U32.is_lt(code,113821))
    case False{}: propertiesBelow1045(code,U32.is_lt(code,113824))
def propertiesBelow1047(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1048(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1049(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1048(code,U32.is_lt(code,118599))
def propertiesBelow1050(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1047(code,U32.is_lt(code,118528))
    case False{}: propertiesBelow1049(code,U32.is_lt(code,118576))
def propertiesBelow1051(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1046(code,U32.is_lt(code,113823))
    case False{}: propertiesBelow1050(code,U32.is_lt(code,118574))
def propertiesBelow1052(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1053(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1054(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1052(code,U32.is_lt(code,119146))
    case False{}: propertiesBelow1053(code,U32.is_lt(code,119171))
def propertiesBelow1055(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1056(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1057(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1056(code,U32.is_lt(code,119362))
def propertiesBelow1058(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1055(code,U32.is_lt(code,119180))
    case False{}: propertiesBelow1057(code,U32.is_lt(code,119214))
def propertiesBelow1059(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1054(code,U32.is_lt(code,119155))
    case False{}: propertiesBelow1058(code,U32.is_lt(code,119210))
def propertiesBelow1060(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1051(code,U32.is_lt(code,113828))
    case False{}: propertiesBelow1059(code,U32.is_lt(code,119173))
def propertiesBelow1061(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1062(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1063(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1061(code,U32.is_lt(code,119808))
    case False{}: propertiesBelow1062(code,U32.is_lt(code,119894))
def propertiesBelow1064(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1065(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1066(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1065(code,U32.is_lt(code,119971))
def propertiesBelow1067(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1064(code,U32.is_lt(code,119966))
    case False{}: propertiesBelow1066(code,U32.is_lt(code,119970))
def propertiesBelow1068(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1063(code,U32.is_lt(code,119893))
    case False{}: propertiesBelow1067(code,U32.is_lt(code,119968))
def propertiesBelow1069(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1070(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1071(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow1070(code,U32.is_lt(code,119982))
def propertiesBelow1072(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1069(code,U32.is_lt(code,119975))
    case False{}: propertiesBelow1071(code,U32.is_lt(code,119981))
def propertiesBelow1073(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1074(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1075(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1074(code,U32.is_lt(code,120004))
def propertiesBelow1076(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1073(code,U32.is_lt(code,119995))
    case False{}: propertiesBelow1075(code,U32.is_lt(code,119997))
def propertiesBelow1077(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1072(code,U32.is_lt(code,119977))
    case False{}: propertiesBelow1076(code,U32.is_lt(code,119996))
def propertiesBelow1078(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1068(code,U32.is_lt(code,119965))
    case False{}: propertiesBelow1077(code,U32.is_lt(code,119994))
def propertiesBelow1079(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1060(code,U32.is_lt(code,119143))
    case False{}: propertiesBelow1078(code,U32.is_lt(code,119973))
def propertiesBelow1080(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1081(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1082(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1080(code,U32.is_lt(code,120070))
    case False{}: propertiesBelow1081(code,U32.is_lt(code,120075))
def propertiesBelow1083(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1084(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1085(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow1084(code,U32.is_lt(code,120094))
def propertiesBelow1086(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1083(code,U32.is_lt(code,120085))
    case False{}: propertiesBelow1085(code,U32.is_lt(code,120093))
def propertiesBelow1087(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1082(code,U32.is_lt(code,120071))
    case False{}: propertiesBelow1086(code,U32.is_lt(code,120086))
def propertiesBelow1088(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1089(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1090(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1089(code,U32.is_lt(code,120133))
def propertiesBelow1091(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1088(code,U32.is_lt(code,120123))
    case False{}: propertiesBelow1090(code,U32.is_lt(code,120128))
def propertiesBelow1092(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1093(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1094(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow1093(code,U32.is_lt(code,120146))
def propertiesBelow1095(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1092(code,U32.is_lt(code,120135))
    case False{}: propertiesBelow1094(code,U32.is_lt(code,120145))
def propertiesBelow1096(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1091(code,U32.is_lt(code,120127))
    case False{}: propertiesBelow1095(code,U32.is_lt(code,120138))
def propertiesBelow1097(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1087(code,U32.is_lt(code,120077))
    case False{}: propertiesBelow1096(code,U32.is_lt(code,120134))
def propertiesBelow1098(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1099(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1098(code,U32.is_lt(code,120488))
    case False{}: propertiesBelow1099(code,U32.is_lt(code,120514))
def propertiesBelow1101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1102(code,U32.is_lt(code,120597))
def propertiesBelow1104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1101(code,U32.is_lt(code,120540))
    case False{}: propertiesBelow1103(code,U32.is_lt(code,120572))
def propertiesBelow1105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1100(code,U32.is_lt(code,120513))
    case False{}: propertiesBelow1104(code,U32.is_lt(code,120571))
def propertiesBelow1106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: propertiesBelow1107(code,U32.is_lt(code,120656))
def propertiesBelow1109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1106(code,U32.is_lt(code,120629))
    case False{}: propertiesBelow1108(code,U32.is_lt(code,120655))
def propertiesBelow1110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1111(code,U32.is_lt(code,120745))
def propertiesBelow1113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1110(code,U32.is_lt(code,120688))
    case False{}: propertiesBelow1112(code,U32.is_lt(code,120714))
def propertiesBelow1114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1109(code,U32.is_lt(code,120630))
    case False{}: propertiesBelow1113(code,U32.is_lt(code,120713))
def propertiesBelow1115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1105(code,U32.is_lt(code,120539))
    case False{}: propertiesBelow1114(code,U32.is_lt(code,120687))
def propertiesBelow1116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1097(code,U32.is_lt(code,120122))
    case False{}: propertiesBelow1115(code,U32.is_lt(code,120598))
def propertiesBelow1117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1079(code,U32.is_lt(code,119365))
    case False{}: propertiesBelow1116(code,U32.is_lt(code,120486))
def propertiesBelow1118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1118(code,U32.is_lt(code,120771))
    case False{}: propertiesBelow1119(code,U32.is_lt(code,120780))
def propertiesBelow1121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1122(code,U32.is_lt(code,121461))
def propertiesBelow1124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1121(code,U32.is_lt(code,121399))
    case False{}: propertiesBelow1123(code,U32.is_lt(code,121453))
def propertiesBelow1125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1120(code,U32.is_lt(code,120772))
    case False{}: propertiesBelow1124(code,U32.is_lt(code,121403))
def propertiesBelow1126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1126(code,U32.is_lt(code,121476))
    case False{}: propertiesBelow1127(code,U32.is_lt(code,121499))
def propertiesBelow1129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1130(code,U32.is_lt(code,122634))
def propertiesBelow1132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1129(code,U32.is_lt(code,121505))
    case False{}: propertiesBelow1131(code,U32.is_lt(code,122624))
def propertiesBelow1133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1128(code,U32.is_lt(code,121477))
    case False{}: propertiesBelow1132(code,U32.is_lt(code,121520))
def propertiesBelow1134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1125(code,U32.is_lt(code,121344))
    case False{}: propertiesBelow1133(code,U32.is_lt(code,121504))
def propertiesBelow1135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1135(code,U32.is_lt(code,122655))
    case False{}: propertiesBelow1136(code,U32.is_lt(code,122667))
def propertiesBelow1138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1139(code,U32.is_lt(code,122907))
def propertiesBelow1141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1138(code,U32.is_lt(code,122887))
    case False{}: propertiesBelow1140(code,U32.is_lt(code,122905))
def propertiesBelow1142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1137(code,U32.is_lt(code,122661))
    case False{}: propertiesBelow1141(code,U32.is_lt(code,122888))
def propertiesBelow1143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1144(code,U32.is_lt(code,122923))
def propertiesBelow1146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1143(code,U32.is_lt(code,122915))
    case False{}: propertiesBelow1145(code,U32.is_lt(code,122918))
def propertiesBelow1147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 0
def propertiesBelow1148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1148(code,U32.is_lt(code,123184))
def propertiesBelow1150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1147(code,U32.is_lt(code,122990))
    case False{}: propertiesBelow1149(code,U32.is_lt(code,123024))
def propertiesBelow1151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1146(code,U32.is_lt(code,122917))
    case False{}: propertiesBelow1150(code,U32.is_lt(code,123023))
def propertiesBelow1152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1142(code,U32.is_lt(code,122880))
    case False{}: propertiesBelow1151(code,U32.is_lt(code,122928))
def propertiesBelow1153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1134(code,U32.is_lt(code,121462))
    case False{}: propertiesBelow1152(code,U32.is_lt(code,122914))
def propertiesBelow1154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1154(code,U32.is_lt(code,123566))
    case False{}: propertiesBelow1155(code,U32.is_lt(code,123628))
def propertiesBelow1157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1158(code,U32.is_lt(code,124400))
def propertiesBelow1160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1157(code,U32.is_lt(code,124139))
    case False{}: propertiesBelow1159(code,U32.is_lt(code,124398))
def propertiesBelow1161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1156(code,U32.is_lt(code,123567))
    case False{}: propertiesBelow1160(code,U32.is_lt(code,124144))
def propertiesBelow1162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1163(code,U32.is_lt(code,124654))
def propertiesBelow1165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1162(code,U32.is_lt(code,124644))
    case False{}: propertiesBelow1164(code,U32.is_lt(code,124647))
def propertiesBelow1166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1167(code,U32.is_lt(code,124672))
def propertiesBelow1169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1166(code,U32.is_lt(code,124661))
    case False{}: propertiesBelow1168(code,U32.is_lt(code,124671))
def propertiesBelow1170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1165(code,U32.is_lt(code,124646))
    case False{}: propertiesBelow1169(code,U32.is_lt(code,124662))
def propertiesBelow1171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1161(code,U32.is_lt(code,123632))
    case False{}: propertiesBelow1170(code,U32.is_lt(code,124656))
def propertiesBelow1172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 2
def propertiesBelow1174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1172(code,U32.is_lt(code,125143))
    case False{}: propertiesBelow1173(code,U32.is_lt(code,125252))
def propertiesBelow1175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def propertiesBelow1176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1176(code,U32.is_lt(code,127338))
def propertiesBelow1178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1175(code,U32.is_lt(code,127280))
    case False{}: propertiesBelow1177(code,U32.is_lt(code,127312))
def propertiesBelow1179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1174(code,U32.is_lt(code,125184))
    case False{}: propertiesBelow1178(code,U32.is_lt(code,127306))
def propertiesBelow1180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def propertiesBelow1181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: propertiesBelow1181(code,U32.is_lt(code,917505))
def propertiesBelow1183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1180(code,U32.is_lt(code,127370))
    case False{}: propertiesBelow1182(code,U32.is_lt(code,128000))
def propertiesBelow1184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 0
def propertiesBelow1186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1185(code,U32.is_lt(code,918000))
def propertiesBelow1187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1184(code,U32.is_lt(code,917536))
    case False{}: propertiesBelow1186(code,U32.is_lt(code,917760))
def propertiesBelow1188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1183(code,U32.is_lt(code,127995))
    case False{}: propertiesBelow1187(code,U32.is_lt(code,917632))
def propertiesBelow1189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1179(code,U32.is_lt(code,125260))
    case False{}: propertiesBelow1188(code,U32.is_lt(code,917506))
def propertiesBelow1190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1171(code,U32.is_lt(code,124643))
    case False{}: propertiesBelow1189(code,U32.is_lt(code,127344))
def propertiesBelow1191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1153(code,U32.is_lt(code,122635))
    case False{}: propertiesBelow1190(code,U32.is_lt(code,125136))
def propertiesBelow1192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1117(code,U32.is_lt(code,120005))
    case False{}: propertiesBelow1191(code,U32.is_lt(code,123198))
def propertiesBelow1193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1043(code,U32.is_lt(code,72874))
    case False{}: propertiesBelow1192(code,U32.is_lt(code,120746))
def propertiesBelow1194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow894(code,U32.is_lt(code,66928))
    case False{}: propertiesBelow1193(code,U32.is_lt(code,110591))
def propertiesBelow1195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow596(code,U32.is_lt(code,4159))
    case False{}: propertiesBelow1194(code,U32.is_lt(code,71102))

def properties(+code: U32) -> U32:
  propertiesBelow1195(code,U32.is_lt(code,42736))

def deltaBelow0(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def deltaBelow1(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def deltaBelow2(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1(code,U32.is_lt(code,215))
def deltaBelow3(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow0(code,U32.is_lt(code,65))
    case False{}: deltaBelow2(code,U32.is_lt(code,192))
def deltaBelow4(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def deltaBelow5(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow6(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow5(code,U32.is_lt(code,258))
def deltaBelow7(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow4(code,U32.is_lt(code,223))
    case False{}: deltaBelow6(code,U32.is_lt(code,257))
def deltaBelow8(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow3(code,U32.is_lt(code,91))
    case False{}: deltaBelow7(code,U32.is_lt(code,256))
def deltaBelow9(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow10(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow11(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow10(code,U32.is_lt(code,263))
def deltaBelow12(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow9(code,U32.is_lt(code,260))
    case False{}: deltaBelow11(code,U32.is_lt(code,262))
def deltaBelow13(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow14(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow15(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow14(code,U32.is_lt(code,268))
def deltaBelow16(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow13(code,U32.is_lt(code,265))
    case False{}: deltaBelow15(code,U32.is_lt(code,267))
def deltaBelow17(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow12(code,U32.is_lt(code,261))
    case False{}: deltaBelow16(code,U32.is_lt(code,266))
def deltaBelow18(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow8(code,U32.is_lt(code,216))
    case False{}: deltaBelow17(code,U32.is_lt(code,264))
def deltaBelow19(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow20(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow21(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow20(code,U32.is_lt(code,273))
def deltaBelow22(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow19(code,U32.is_lt(code,270))
    case False{}: deltaBelow21(code,U32.is_lt(code,272))
def deltaBelow23(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow24(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow25(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow24(code,U32.is_lt(code,278))
def deltaBelow26(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow23(code,U32.is_lt(code,275))
    case False{}: deltaBelow25(code,U32.is_lt(code,277))
def deltaBelow27(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow22(code,U32.is_lt(code,271))
    case False{}: deltaBelow26(code,U32.is_lt(code,276))
def deltaBelow28(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow29(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow30(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow29(code,U32.is_lt(code,283))
def deltaBelow31(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow28(code,U32.is_lt(code,280))
    case False{}: deltaBelow30(code,U32.is_lt(code,282))
def deltaBelow32(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow33(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow34(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow33(code,U32.is_lt(code,288))
def deltaBelow35(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow32(code,U32.is_lt(code,285))
    case False{}: deltaBelow34(code,U32.is_lt(code,287))
def deltaBelow36(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow31(code,U32.is_lt(code,281))
    case False{}: deltaBelow35(code,U32.is_lt(code,286))
def deltaBelow37(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow27(code,U32.is_lt(code,274))
    case False{}: deltaBelow36(code,U32.is_lt(code,284))
def deltaBelow38(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow18(code,U32.is_lt(code,259))
    case False{}: deltaBelow37(code,U32.is_lt(code,279))
def deltaBelow39(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow40(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow41(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow40(code,U32.is_lt(code,293))
def deltaBelow42(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow39(code,U32.is_lt(code,290))
    case False{}: deltaBelow41(code,U32.is_lt(code,292))
def deltaBelow43(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow44(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow45(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow44(code,U32.is_lt(code,298))
def deltaBelow46(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow43(code,U32.is_lt(code,295))
    case False{}: deltaBelow45(code,U32.is_lt(code,297))
def deltaBelow47(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow42(code,U32.is_lt(code,291))
    case False{}: deltaBelow46(code,U32.is_lt(code,296))
def deltaBelow48(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow49(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow50(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow49(code,U32.is_lt(code,303))
def deltaBelow51(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow48(code,U32.is_lt(code,300))
    case False{}: deltaBelow50(code,U32.is_lt(code,302))
def deltaBelow52(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow53(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow54(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow53(code,U32.is_lt(code,310))
def deltaBelow55(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow52(code,U32.is_lt(code,307))
    case False{}: deltaBelow54(code,U32.is_lt(code,309))
def deltaBelow56(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow51(code,U32.is_lt(code,301))
    case False{}: deltaBelow55(code,U32.is_lt(code,308))
def deltaBelow57(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow47(code,U32.is_lt(code,294))
    case False{}: deltaBelow56(code,U32.is_lt(code,306))
def deltaBelow58(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow59(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow60(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow59(code,U32.is_lt(code,316))
def deltaBelow61(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow58(code,U32.is_lt(code,313))
    case False{}: deltaBelow60(code,U32.is_lt(code,315))
def deltaBelow62(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow63(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow64(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow63(code,U32.is_lt(code,321))
def deltaBelow65(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow62(code,U32.is_lt(code,318))
    case False{}: deltaBelow64(code,U32.is_lt(code,320))
def deltaBelow66(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow61(code,U32.is_lt(code,314))
    case False{}: deltaBelow65(code,U32.is_lt(code,319))
def deltaBelow67(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow68(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow69(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow68(code,U32.is_lt(code,326))
def deltaBelow70(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow67(code,U32.is_lt(code,323))
    case False{}: deltaBelow69(code,U32.is_lt(code,325))
def deltaBelow71(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow72(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow73(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow72(code,U32.is_lt(code,332))
def deltaBelow74(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow71(code,U32.is_lt(code,328))
    case False{}: deltaBelow73(code,U32.is_lt(code,331))
def deltaBelow75(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow70(code,U32.is_lt(code,324))
    case False{}: deltaBelow74(code,U32.is_lt(code,330))
def deltaBelow76(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow66(code,U32.is_lt(code,317))
    case False{}: deltaBelow75(code,U32.is_lt(code,327))
def deltaBelow77(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow57(code,U32.is_lt(code,299))
    case False{}: deltaBelow76(code,U32.is_lt(code,322))
def deltaBelow78(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow38(code,U32.is_lt(code,269))
    case False{}: deltaBelow77(code,U32.is_lt(code,311))
def deltaBelow79(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow80(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow81(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow80(code,U32.is_lt(code,337))
def deltaBelow82(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow79(code,U32.is_lt(code,334))
    case False{}: deltaBelow81(code,U32.is_lt(code,336))
def deltaBelow83(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow84(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow85(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow84(code,U32.is_lt(code,342))
def deltaBelow86(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow83(code,U32.is_lt(code,339))
    case False{}: deltaBelow85(code,U32.is_lt(code,341))
def deltaBelow87(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow82(code,U32.is_lt(code,335))
    case False{}: deltaBelow86(code,U32.is_lt(code,340))
def deltaBelow88(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow89(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow90(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow89(code,U32.is_lt(code,347))
def deltaBelow91(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow88(code,U32.is_lt(code,344))
    case False{}: deltaBelow90(code,U32.is_lt(code,346))
def deltaBelow92(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow93(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow94(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow93(code,U32.is_lt(code,352))
def deltaBelow95(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow92(code,U32.is_lt(code,349))
    case False{}: deltaBelow94(code,U32.is_lt(code,351))
def deltaBelow96(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow91(code,U32.is_lt(code,345))
    case False{}: deltaBelow95(code,U32.is_lt(code,350))
def deltaBelow97(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow87(code,U32.is_lt(code,338))
    case False{}: deltaBelow96(code,U32.is_lt(code,348))
def deltaBelow98(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow99(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow99(code,U32.is_lt(code,357))
def deltaBelow101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow98(code,U32.is_lt(code,354))
    case False{}: deltaBelow100(code,U32.is_lt(code,356))
def deltaBelow102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow103(code,U32.is_lt(code,362))
def deltaBelow105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow102(code,U32.is_lt(code,359))
    case False{}: deltaBelow104(code,U32.is_lt(code,361))
def deltaBelow106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow101(code,U32.is_lt(code,355))
    case False{}: deltaBelow105(code,U32.is_lt(code,360))
def deltaBelow107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow108(code,U32.is_lt(code,367))
def deltaBelow110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow107(code,U32.is_lt(code,364))
    case False{}: deltaBelow109(code,U32.is_lt(code,366))
def deltaBelow111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow112(code,U32.is_lt(code,372))
def deltaBelow114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow111(code,U32.is_lt(code,369))
    case False{}: deltaBelow113(code,U32.is_lt(code,371))
def deltaBelow115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow110(code,U32.is_lt(code,365))
    case False{}: deltaBelow114(code,U32.is_lt(code,370))
def deltaBelow116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow106(code,U32.is_lt(code,358))
    case False{}: deltaBelow115(code,U32.is_lt(code,368))
def deltaBelow117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow97(code,U32.is_lt(code,343))
    case False{}: deltaBelow116(code,U32.is_lt(code,363))
def deltaBelow118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967175
    case False{}: 1
def deltaBelow120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow119(code,U32.is_lt(code,377))
def deltaBelow121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow118(code,U32.is_lt(code,374))
    case False{}: deltaBelow120(code,U32.is_lt(code,376))
def deltaBelow122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow123(code,U32.is_lt(code,382))
def deltaBelow125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow122(code,U32.is_lt(code,379))
    case False{}: deltaBelow124(code,U32.is_lt(code,381))
def deltaBelow126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow121(code,U32.is_lt(code,375))
    case False{}: deltaBelow125(code,U32.is_lt(code,380))
def deltaBelow127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 210
    case False{}: 1
def deltaBelow128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow128(code,U32.is_lt(code,389))
def deltaBelow130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow127(code,U32.is_lt(code,386))
    case False{}: deltaBelow129(code,U32.is_lt(code,388))
def deltaBelow131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 206
    case False{}: 1
def deltaBelow132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 205
    case False{}: 1
def deltaBelow133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow132(code,U32.is_lt(code,395))
def deltaBelow134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow131(code,U32.is_lt(code,391))
    case False{}: deltaBelow133(code,U32.is_lt(code,393))
def deltaBelow135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow130(code,U32.is_lt(code,387))
    case False{}: deltaBelow134(code,U32.is_lt(code,392))
def deltaBelow136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow126(code,U32.is_lt(code,378))
    case False{}: deltaBelow135(code,U32.is_lt(code,390))
def deltaBelow137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 79
def deltaBelow138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 203
    case False{}: 1
def deltaBelow139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 202
    case False{}: deltaBelow138(code,U32.is_lt(code,401))
def deltaBelow140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow137(code,U32.is_lt(code,398))
    case False{}: deltaBelow139(code,U32.is_lt(code,400))
def deltaBelow141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 205
def deltaBelow142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 211
def deltaBelow143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 207
    case False{}: deltaBelow142(code,U32.is_lt(code,406))
def deltaBelow144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow141(code,U32.is_lt(code,403))
    case False{}: deltaBelow143(code,U32.is_lt(code,405))
def deltaBelow145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow140(code,U32.is_lt(code,399))
    case False{}: deltaBelow144(code,U32.is_lt(code,404))
def deltaBelow146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 209
    case False{}: 1
def deltaBelow147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 211
    case False{}: 213
def deltaBelow148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow147(code,U32.is_lt(code,413))
def deltaBelow149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow146(code,U32.is_lt(code,408))
    case False{}: deltaBelow148(code,U32.is_lt(code,412))
def deltaBelow150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 214
    case False{}: 1
def deltaBelow151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow150(code,U32.is_lt(code,416))
def deltaBelow152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow152(code,U32.is_lt(code,419))
def deltaBelow154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow151(code,U32.is_lt(code,415))
    case False{}: deltaBelow153(code,U32.is_lt(code,418))
def deltaBelow155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow149(code,U32.is_lt(code,409))
    case False{}: deltaBelow154(code,U32.is_lt(code,417))
def deltaBelow156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow145(code,U32.is_lt(code,402))
    case False{}: deltaBelow155(code,U32.is_lt(code,414))
def deltaBelow157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow136(code,U32.is_lt(code,385))
    case False{}: deltaBelow156(code,U32.is_lt(code,407))
def deltaBelow158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow117(code,U32.is_lt(code,353))
    case False{}: deltaBelow157(code,U32.is_lt(code,396))
def deltaBelow159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow78(code,U32.is_lt(code,289))
    case False{}: deltaBelow158(code,U32.is_lt(code,373))
def deltaBelow160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 218
    case False{}: deltaBelow161(code,U32.is_lt(code,424))
def deltaBelow163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow160(code,U32.is_lt(code,421))
    case False{}: deltaBelow162(code,U32.is_lt(code,423))
def deltaBelow164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 218
    case False{}: 0
def deltaBelow165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 218
def deltaBelow166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow165(code,U32.is_lt(code,430))
def deltaBelow167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow164(code,U32.is_lt(code,426))
    case False{}: deltaBelow166(code,U32.is_lt(code,429))
def deltaBelow168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow163(code,U32.is_lt(code,422))
    case False{}: deltaBelow167(code,U32.is_lt(code,428))
def deltaBelow169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 217
    case False{}: deltaBelow170(code,U32.is_lt(code,436))
def deltaBelow172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow169(code,U32.is_lt(code,432))
    case False{}: deltaBelow171(code,U32.is_lt(code,435))
def deltaBelow173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 219
    case False{}: deltaBelow174(code,U32.is_lt(code,441))
def deltaBelow176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow173(code,U32.is_lt(code,438))
    case False{}: deltaBelow175(code,U32.is_lt(code,440))
def deltaBelow177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow172(code,U32.is_lt(code,433))
    case False{}: deltaBelow176(code,U32.is_lt(code,439))
def deltaBelow178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow168(code,U32.is_lt(code,425))
    case False{}: deltaBelow177(code,U32.is_lt(code,437))
def deltaBelow179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: deltaBelow180(code,U32.is_lt(code,454))
def deltaBelow182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow179(code,U32.is_lt(code,445))
    case False{}: deltaBelow181(code,U32.is_lt(code,453))
def deltaBelow183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def deltaBelow184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def deltaBelow185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow184(code,U32.is_lt(code,459))
def deltaBelow186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow183(code,U32.is_lt(code,456))
    case False{}: deltaBelow185(code,U32.is_lt(code,458))
def deltaBelow187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow182(code,U32.is_lt(code,452))
    case False{}: deltaBelow186(code,U32.is_lt(code,457))
def deltaBelow188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow189(code,U32.is_lt(code,464))
def deltaBelow191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow188(code,U32.is_lt(code,461))
    case False{}: deltaBelow190(code,U32.is_lt(code,463))
def deltaBelow192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow193(code,U32.is_lt(code,469))
def deltaBelow195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow192(code,U32.is_lt(code,466))
    case False{}: deltaBelow194(code,U32.is_lt(code,468))
def deltaBelow196(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow191(code,U32.is_lt(code,462))
    case False{}: deltaBelow195(code,U32.is_lt(code,467))
def deltaBelow197(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow187(code,U32.is_lt(code,455))
    case False{}: deltaBelow196(code,U32.is_lt(code,465))
def deltaBelow198(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow178(code,U32.is_lt(code,431))
    case False{}: deltaBelow197(code,U32.is_lt(code,460))
def deltaBelow199(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow200(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow201(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow200(code,U32.is_lt(code,474))
def deltaBelow202(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow199(code,U32.is_lt(code,471))
    case False{}: deltaBelow201(code,U32.is_lt(code,473))
def deltaBelow203(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow204(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow205(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow204(code,U32.is_lt(code,480))
def deltaBelow206(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow203(code,U32.is_lt(code,476))
    case False{}: deltaBelow205(code,U32.is_lt(code,479))
def deltaBelow207(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow202(code,U32.is_lt(code,472))
    case False{}: deltaBelow206(code,U32.is_lt(code,478))
def deltaBelow208(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow209(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow210(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow209(code,U32.is_lt(code,485))
def deltaBelow211(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow208(code,U32.is_lt(code,482))
    case False{}: deltaBelow210(code,U32.is_lt(code,484))
def deltaBelow212(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow213(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow214(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow213(code,U32.is_lt(code,490))
def deltaBelow215(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow212(code,U32.is_lt(code,487))
    case False{}: deltaBelow214(code,U32.is_lt(code,489))
def deltaBelow216(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow211(code,U32.is_lt(code,483))
    case False{}: deltaBelow215(code,U32.is_lt(code,488))
def deltaBelow217(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow207(code,U32.is_lt(code,475))
    case False{}: deltaBelow216(code,U32.is_lt(code,486))
def deltaBelow218(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow219(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow220(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow219(code,U32.is_lt(code,495))
def deltaBelow221(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow218(code,U32.is_lt(code,492))
    case False{}: deltaBelow220(code,U32.is_lt(code,494))
def deltaBelow222(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 2
    case False{}: 1
def deltaBelow223(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow224(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow223(code,U32.is_lt(code,501))
def deltaBelow225(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow222(code,U32.is_lt(code,498))
    case False{}: deltaBelow224(code,U32.is_lt(code,500))
def deltaBelow226(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow221(code,U32.is_lt(code,493))
    case False{}: deltaBelow225(code,U32.is_lt(code,499))
def deltaBelow227(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967199
    case False{}: 4294967240
def deltaBelow228(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow229(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow228(code,U32.is_lt(code,506))
def deltaBelow230(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow227(code,U32.is_lt(code,503))
    case False{}: deltaBelow229(code,U32.is_lt(code,505))
def deltaBelow231(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow232(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow231(code,U32.is_lt(code,509))
def deltaBelow233(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow234(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow233(code,U32.is_lt(code,512))
def deltaBelow235(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow232(code,U32.is_lt(code,508))
    case False{}: deltaBelow234(code,U32.is_lt(code,511))
def deltaBelow236(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow230(code,U32.is_lt(code,504))
    case False{}: deltaBelow235(code,U32.is_lt(code,510))
def deltaBelow237(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow226(code,U32.is_lt(code,497))
    case False{}: deltaBelow236(code,U32.is_lt(code,507))
def deltaBelow238(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow217(code,U32.is_lt(code,481))
    case False{}: deltaBelow237(code,U32.is_lt(code,502))
def deltaBelow239(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow198(code,U32.is_lt(code,444))
    case False{}: deltaBelow238(code,U32.is_lt(code,491))
def deltaBelow240(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow241(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow242(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow241(code,U32.is_lt(code,517))
def deltaBelow243(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow240(code,U32.is_lt(code,514))
    case False{}: deltaBelow242(code,U32.is_lt(code,516))
def deltaBelow244(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow245(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow246(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow245(code,U32.is_lt(code,522))
def deltaBelow247(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow244(code,U32.is_lt(code,519))
    case False{}: deltaBelow246(code,U32.is_lt(code,521))
def deltaBelow248(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow243(code,U32.is_lt(code,515))
    case False{}: deltaBelow247(code,U32.is_lt(code,520))
def deltaBelow249(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow250(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow251(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow250(code,U32.is_lt(code,527))
def deltaBelow252(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow249(code,U32.is_lt(code,524))
    case False{}: deltaBelow251(code,U32.is_lt(code,526))
def deltaBelow253(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow254(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow255(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow254(code,U32.is_lt(code,532))
def deltaBelow256(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow253(code,U32.is_lt(code,529))
    case False{}: deltaBelow255(code,U32.is_lt(code,531))
def deltaBelow257(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow252(code,U32.is_lt(code,525))
    case False{}: deltaBelow256(code,U32.is_lt(code,530))
def deltaBelow258(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow248(code,U32.is_lt(code,518))
    case False{}: deltaBelow257(code,U32.is_lt(code,528))
def deltaBelow259(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow260(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow261(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow260(code,U32.is_lt(code,537))
def deltaBelow262(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow259(code,U32.is_lt(code,534))
    case False{}: deltaBelow261(code,U32.is_lt(code,536))
def deltaBelow263(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow264(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow265(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow264(code,U32.is_lt(code,542))
def deltaBelow266(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow263(code,U32.is_lt(code,539))
    case False{}: deltaBelow265(code,U32.is_lt(code,541))
def deltaBelow267(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow262(code,U32.is_lt(code,535))
    case False{}: deltaBelow266(code,U32.is_lt(code,540))
def deltaBelow268(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967166
def deltaBelow269(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow270(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow269(code,U32.is_lt(code,547))
def deltaBelow271(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow268(code,U32.is_lt(code,544))
    case False{}: deltaBelow270(code,U32.is_lt(code,546))
def deltaBelow272(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow273(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow274(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow273(code,U32.is_lt(code,552))
def deltaBelow275(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow272(code,U32.is_lt(code,549))
    case False{}: deltaBelow274(code,U32.is_lt(code,551))
def deltaBelow276(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow271(code,U32.is_lt(code,545))
    case False{}: deltaBelow275(code,U32.is_lt(code,550))
def deltaBelow277(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow267(code,U32.is_lt(code,538))
    case False{}: deltaBelow276(code,U32.is_lt(code,548))
def deltaBelow278(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow258(code,U32.is_lt(code,523))
    case False{}: deltaBelow277(code,U32.is_lt(code,543))
def deltaBelow279(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow280(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow281(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow280(code,U32.is_lt(code,557))
def deltaBelow282(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow279(code,U32.is_lt(code,554))
    case False{}: deltaBelow281(code,U32.is_lt(code,556))
def deltaBelow283(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow284(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow285(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow284(code,U32.is_lt(code,562))
def deltaBelow286(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow283(code,U32.is_lt(code,559))
    case False{}: deltaBelow285(code,U32.is_lt(code,561))
def deltaBelow287(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow282(code,U32.is_lt(code,555))
    case False{}: deltaBelow286(code,U32.is_lt(code,560))
def deltaBelow288(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10795
def deltaBelow289(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967133
def deltaBelow290(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow289(code,U32.is_lt(code,573))
def deltaBelow291(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow288(code,U32.is_lt(code,570))
    case False{}: deltaBelow290(code,U32.is_lt(code,572))
def deltaBelow292(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10792
    case False{}: 0
def deltaBelow293(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967101
def deltaBelow294(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow293(code,U32.is_lt(code,579))
def deltaBelow295(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow292(code,U32.is_lt(code,575))
    case False{}: deltaBelow294(code,U32.is_lt(code,578))
def deltaBelow296(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow291(code,U32.is_lt(code,571))
    case False{}: deltaBelow295(code,U32.is_lt(code,577))
def deltaBelow297(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow287(code,U32.is_lt(code,558))
    case False{}: deltaBelow296(code,U32.is_lt(code,574))
def deltaBelow298(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 69
    case False{}: 71
def deltaBelow299(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow300(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow299(code,U32.is_lt(code,584))
def deltaBelow301(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow298(code,U32.is_lt(code,581))
    case False{}: deltaBelow300(code,U32.is_lt(code,583))
def deltaBelow302(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow303(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow304(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow303(code,U32.is_lt(code,589))
def deltaBelow305(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow302(code,U32.is_lt(code,586))
    case False{}: deltaBelow304(code,U32.is_lt(code,588))
def deltaBelow306(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow301(code,U32.is_lt(code,582))
    case False{}: deltaBelow305(code,U32.is_lt(code,587))
def deltaBelow307(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow308(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow309(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow308(code,U32.is_lt(code,882))
def deltaBelow310(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow307(code,U32.is_lt(code,591))
    case False{}: deltaBelow309(code,U32.is_lt(code,881))
def deltaBelow311(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow312(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow311(code,U32.is_lt(code,887))
def deltaBelow313(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 38
def deltaBelow314(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 116
    case False{}: deltaBelow313(code,U32.is_lt(code,902))
def deltaBelow315(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow312(code,U32.is_lt(code,886))
    case False{}: deltaBelow314(code,U32.is_lt(code,896))
def deltaBelow316(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow310(code,U32.is_lt(code,880))
    case False{}: deltaBelow315(code,U32.is_lt(code,895))
def deltaBelow317(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow306(code,U32.is_lt(code,585))
    case False{}: deltaBelow316(code,U32.is_lt(code,883))
def deltaBelow318(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow297(code,U32.is_lt(code,563))
    case False{}: deltaBelow317(code,U32.is_lt(code,590))
def deltaBelow319(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow278(code,U32.is_lt(code,533))
    case False{}: deltaBelow318(code,U32.is_lt(code,580))
def deltaBelow320(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow239(code,U32.is_lt(code,470))
    case False{}: deltaBelow319(code,U32.is_lt(code,553))
def deltaBelow321(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow159(code,U32.is_lt(code,333))
    case False{}: deltaBelow320(code,U32.is_lt(code,513))
def deltaBelow322(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 37
def deltaBelow323(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 64
    case False{}: 0
def deltaBelow324(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow323(code,U32.is_lt(code,909))
def deltaBelow325(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow322(code,U32.is_lt(code,904))
    case False{}: deltaBelow324(code,U32.is_lt(code,908))
def deltaBelow326(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 63
    case False{}: 0
def deltaBelow327(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def deltaBelow328(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: deltaBelow327(code,U32.is_lt(code,931))
def deltaBelow329(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow326(code,U32.is_lt(code,912))
    case False{}: deltaBelow328(code,U32.is_lt(code,930))
def deltaBelow330(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow325(code,U32.is_lt(code,907))
    case False{}: deltaBelow329(code,U32.is_lt(code,913))
def deltaBelow331(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def deltaBelow332(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow333(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow332(code,U32.is_lt(code,985))
def deltaBelow334(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow331(code,U32.is_lt(code,975))
    case False{}: deltaBelow333(code,U32.is_lt(code,984))
def deltaBelow335(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow336(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow337(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow336(code,U32.is_lt(code,990))
def deltaBelow338(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow335(code,U32.is_lt(code,987))
    case False{}: deltaBelow337(code,U32.is_lt(code,989))
def deltaBelow339(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow334(code,U32.is_lt(code,976))
    case False{}: deltaBelow338(code,U32.is_lt(code,988))
def deltaBelow340(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow330(code,U32.is_lt(code,910))
    case False{}: deltaBelow339(code,U32.is_lt(code,986))
def deltaBelow341(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow342(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow343(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow342(code,U32.is_lt(code,995))
def deltaBelow344(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow341(code,U32.is_lt(code,992))
    case False{}: deltaBelow343(code,U32.is_lt(code,994))
def deltaBelow345(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow346(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow347(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow346(code,U32.is_lt(code,1000))
def deltaBelow348(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow345(code,U32.is_lt(code,997))
    case False{}: deltaBelow347(code,U32.is_lt(code,999))
def deltaBelow349(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow344(code,U32.is_lt(code,993))
    case False{}: deltaBelow348(code,U32.is_lt(code,998))
def deltaBelow350(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow351(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow352(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow351(code,U32.is_lt(code,1005))
def deltaBelow353(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow350(code,U32.is_lt(code,1002))
    case False{}: deltaBelow352(code,U32.is_lt(code,1004))
def deltaBelow354(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow355(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow356(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967236
    case False{}: deltaBelow355(code,U32.is_lt(code,1015))
def deltaBelow357(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow354(code,U32.is_lt(code,1007))
    case False{}: deltaBelow356(code,U32.is_lt(code,1013))
def deltaBelow358(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow353(code,U32.is_lt(code,1003))
    case False{}: deltaBelow357(code,U32.is_lt(code,1012))
def deltaBelow359(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow349(code,U32.is_lt(code,996))
    case False{}: deltaBelow358(code,U32.is_lt(code,1006))
def deltaBelow360(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow340(code,U32.is_lt(code,940))
    case False{}: deltaBelow359(code,U32.is_lt(code,1001))
def deltaBelow361(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967289
def deltaBelow362(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967166
def deltaBelow363(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow362(code,U32.is_lt(code,1021))
def deltaBelow364(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow361(code,U32.is_lt(code,1017))
    case False{}: deltaBelow363(code,U32.is_lt(code,1019))
def deltaBelow365(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 80
    case False{}: 32
def deltaBelow366(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow367(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow366(code,U32.is_lt(code,1121))
def deltaBelow368(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow365(code,U32.is_lt(code,1040))
    case False{}: deltaBelow367(code,U32.is_lt(code,1120))
def deltaBelow369(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow364(code,U32.is_lt(code,1018))
    case False{}: deltaBelow368(code,U32.is_lt(code,1072))
def deltaBelow370(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow371(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow372(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow371(code,U32.is_lt(code,1126))
def deltaBelow373(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow370(code,U32.is_lt(code,1123))
    case False{}: deltaBelow372(code,U32.is_lt(code,1125))
def deltaBelow374(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow375(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow376(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow375(code,U32.is_lt(code,1131))
def deltaBelow377(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow374(code,U32.is_lt(code,1128))
    case False{}: deltaBelow376(code,U32.is_lt(code,1130))
def deltaBelow378(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow373(code,U32.is_lt(code,1124))
    case False{}: deltaBelow377(code,U32.is_lt(code,1129))
def deltaBelow379(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow369(code,U32.is_lt(code,1024))
    case False{}: deltaBelow378(code,U32.is_lt(code,1127))
def deltaBelow380(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow381(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow382(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow381(code,U32.is_lt(code,1136))
def deltaBelow383(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow380(code,U32.is_lt(code,1133))
    case False{}: deltaBelow382(code,U32.is_lt(code,1135))
def deltaBelow384(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow385(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow386(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow385(code,U32.is_lt(code,1141))
def deltaBelow387(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow384(code,U32.is_lt(code,1138))
    case False{}: deltaBelow386(code,U32.is_lt(code,1140))
def deltaBelow388(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow383(code,U32.is_lt(code,1134))
    case False{}: deltaBelow387(code,U32.is_lt(code,1139))
def deltaBelow389(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow390(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow391(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow390(code,U32.is_lt(code,1146))
def deltaBelow392(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow389(code,U32.is_lt(code,1143))
    case False{}: deltaBelow391(code,U32.is_lt(code,1145))
def deltaBelow393(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow394(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow393(code,U32.is_lt(code,1149))
def deltaBelow395(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow396(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow395(code,U32.is_lt(code,1152))
def deltaBelow397(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow394(code,U32.is_lt(code,1148))
    case False{}: deltaBelow396(code,U32.is_lt(code,1151))
def deltaBelow398(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow392(code,U32.is_lt(code,1144))
    case False{}: deltaBelow397(code,U32.is_lt(code,1150))
def deltaBelow399(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow388(code,U32.is_lt(code,1137))
    case False{}: deltaBelow398(code,U32.is_lt(code,1147))
def deltaBelow400(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow379(code,U32.is_lt(code,1122))
    case False{}: deltaBelow399(code,U32.is_lt(code,1142))
def deltaBelow401(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow360(code,U32.is_lt(code,991))
    case False{}: deltaBelow400(code,U32.is_lt(code,1132))
def deltaBelow402(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow403(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow404(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow403(code,U32.is_lt(code,1165))
def deltaBelow405(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow402(code,U32.is_lt(code,1162))
    case False{}: deltaBelow404(code,U32.is_lt(code,1164))
def deltaBelow406(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow407(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow408(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow407(code,U32.is_lt(code,1170))
def deltaBelow409(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow406(code,U32.is_lt(code,1167))
    case False{}: deltaBelow408(code,U32.is_lt(code,1169))
def deltaBelow410(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow405(code,U32.is_lt(code,1163))
    case False{}: deltaBelow409(code,U32.is_lt(code,1168))
def deltaBelow411(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow412(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow413(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow412(code,U32.is_lt(code,1175))
def deltaBelow414(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow411(code,U32.is_lt(code,1172))
    case False{}: deltaBelow413(code,U32.is_lt(code,1174))
def deltaBelow415(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow416(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow417(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow416(code,U32.is_lt(code,1180))
def deltaBelow418(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow415(code,U32.is_lt(code,1177))
    case False{}: deltaBelow417(code,U32.is_lt(code,1179))
def deltaBelow419(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow414(code,U32.is_lt(code,1173))
    case False{}: deltaBelow418(code,U32.is_lt(code,1178))
def deltaBelow420(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow410(code,U32.is_lt(code,1166))
    case False{}: deltaBelow419(code,U32.is_lt(code,1176))
def deltaBelow421(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow422(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow423(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow422(code,U32.is_lt(code,1185))
def deltaBelow424(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow421(code,U32.is_lt(code,1182))
    case False{}: deltaBelow423(code,U32.is_lt(code,1184))
def deltaBelow425(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow426(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow427(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow426(code,U32.is_lt(code,1190))
def deltaBelow428(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow425(code,U32.is_lt(code,1187))
    case False{}: deltaBelow427(code,U32.is_lt(code,1189))
def deltaBelow429(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow424(code,U32.is_lt(code,1183))
    case False{}: deltaBelow428(code,U32.is_lt(code,1188))
def deltaBelow430(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow431(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow432(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow431(code,U32.is_lt(code,1195))
def deltaBelow433(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow430(code,U32.is_lt(code,1192))
    case False{}: deltaBelow432(code,U32.is_lt(code,1194))
def deltaBelow434(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow435(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow436(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow435(code,U32.is_lt(code,1200))
def deltaBelow437(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow434(code,U32.is_lt(code,1197))
    case False{}: deltaBelow436(code,U32.is_lt(code,1199))
def deltaBelow438(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow433(code,U32.is_lt(code,1193))
    case False{}: deltaBelow437(code,U32.is_lt(code,1198))
def deltaBelow439(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow429(code,U32.is_lt(code,1186))
    case False{}: deltaBelow438(code,U32.is_lt(code,1196))
def deltaBelow440(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow420(code,U32.is_lt(code,1171))
    case False{}: deltaBelow439(code,U32.is_lt(code,1191))
def deltaBelow441(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow442(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow443(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow442(code,U32.is_lt(code,1205))
def deltaBelow444(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow441(code,U32.is_lt(code,1202))
    case False{}: deltaBelow443(code,U32.is_lt(code,1204))
def deltaBelow445(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow446(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow447(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow446(code,U32.is_lt(code,1210))
def deltaBelow448(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow445(code,U32.is_lt(code,1207))
    case False{}: deltaBelow447(code,U32.is_lt(code,1209))
def deltaBelow449(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow444(code,U32.is_lt(code,1203))
    case False{}: deltaBelow448(code,U32.is_lt(code,1208))
def deltaBelow450(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow451(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow452(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow451(code,U32.is_lt(code,1215))
def deltaBelow453(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow450(code,U32.is_lt(code,1212))
    case False{}: deltaBelow452(code,U32.is_lt(code,1214))
def deltaBelow454(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 15
    case False{}: 1
def deltaBelow455(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow456(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow455(code,U32.is_lt(code,1220))
def deltaBelow457(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow454(code,U32.is_lt(code,1217))
    case False{}: deltaBelow456(code,U32.is_lt(code,1219))
def deltaBelow458(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow453(code,U32.is_lt(code,1213))
    case False{}: deltaBelow457(code,U32.is_lt(code,1218))
def deltaBelow459(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow449(code,U32.is_lt(code,1206))
    case False{}: deltaBelow458(code,U32.is_lt(code,1216))
def deltaBelow460(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow461(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow462(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow461(code,U32.is_lt(code,1225))
def deltaBelow463(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow460(code,U32.is_lt(code,1222))
    case False{}: deltaBelow462(code,U32.is_lt(code,1224))
def deltaBelow464(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow465(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow466(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow465(code,U32.is_lt(code,1230))
def deltaBelow467(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow464(code,U32.is_lt(code,1227))
    case False{}: deltaBelow466(code,U32.is_lt(code,1229))
def deltaBelow468(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow463(code,U32.is_lt(code,1223))
    case False{}: deltaBelow467(code,U32.is_lt(code,1228))
def deltaBelow469(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow470(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow471(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow470(code,U32.is_lt(code,1236))
def deltaBelow472(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow469(code,U32.is_lt(code,1233))
    case False{}: deltaBelow471(code,U32.is_lt(code,1235))
def deltaBelow473(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow474(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow473(code,U32.is_lt(code,1239))
def deltaBelow475(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow476(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow475(code,U32.is_lt(code,1242))
def deltaBelow477(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow474(code,U32.is_lt(code,1238))
    case False{}: deltaBelow476(code,U32.is_lt(code,1241))
def deltaBelow478(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow472(code,U32.is_lt(code,1234))
    case False{}: deltaBelow477(code,U32.is_lt(code,1240))
def deltaBelow479(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow468(code,U32.is_lt(code,1226))
    case False{}: deltaBelow478(code,U32.is_lt(code,1237))
def deltaBelow480(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow459(code,U32.is_lt(code,1211))
    case False{}: deltaBelow479(code,U32.is_lt(code,1232))
def deltaBelow481(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow440(code,U32.is_lt(code,1181))
    case False{}: deltaBelow480(code,U32.is_lt(code,1221))
def deltaBelow482(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow401(code,U32.is_lt(code,1016))
    case False{}: deltaBelow481(code,U32.is_lt(code,1201))
def deltaBelow483(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow484(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow485(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow484(code,U32.is_lt(code,1247))
def deltaBelow486(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow483(code,U32.is_lt(code,1244))
    case False{}: deltaBelow485(code,U32.is_lt(code,1246))
def deltaBelow487(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow488(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow489(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow488(code,U32.is_lt(code,1252))
def deltaBelow490(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow487(code,U32.is_lt(code,1249))
    case False{}: deltaBelow489(code,U32.is_lt(code,1251))
def deltaBelow491(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow486(code,U32.is_lt(code,1245))
    case False{}: deltaBelow490(code,U32.is_lt(code,1250))
def deltaBelow492(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow493(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow494(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow493(code,U32.is_lt(code,1257))
def deltaBelow495(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow492(code,U32.is_lt(code,1254))
    case False{}: deltaBelow494(code,U32.is_lt(code,1256))
def deltaBelow496(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow497(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow498(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow497(code,U32.is_lt(code,1262))
def deltaBelow499(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow496(code,U32.is_lt(code,1259))
    case False{}: deltaBelow498(code,U32.is_lt(code,1261))
def deltaBelow500(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow495(code,U32.is_lt(code,1255))
    case False{}: deltaBelow499(code,U32.is_lt(code,1260))
def deltaBelow501(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow491(code,U32.is_lt(code,1248))
    case False{}: deltaBelow500(code,U32.is_lt(code,1258))
def deltaBelow502(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow503(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow504(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow503(code,U32.is_lt(code,1267))
def deltaBelow505(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow502(code,U32.is_lt(code,1264))
    case False{}: deltaBelow504(code,U32.is_lt(code,1266))
def deltaBelow506(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow507(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow508(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow507(code,U32.is_lt(code,1272))
def deltaBelow509(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow506(code,U32.is_lt(code,1269))
    case False{}: deltaBelow508(code,U32.is_lt(code,1271))
def deltaBelow510(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow505(code,U32.is_lt(code,1265))
    case False{}: deltaBelow509(code,U32.is_lt(code,1270))
def deltaBelow511(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow512(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow513(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow512(code,U32.is_lt(code,1277))
def deltaBelow514(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow511(code,U32.is_lt(code,1274))
    case False{}: deltaBelow513(code,U32.is_lt(code,1276))
def deltaBelow515(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow516(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow517(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow516(code,U32.is_lt(code,1282))
def deltaBelow518(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow515(code,U32.is_lt(code,1279))
    case False{}: deltaBelow517(code,U32.is_lt(code,1281))
def deltaBelow519(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow514(code,U32.is_lt(code,1275))
    case False{}: deltaBelow518(code,U32.is_lt(code,1280))
def deltaBelow520(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow510(code,U32.is_lt(code,1268))
    case False{}: deltaBelow519(code,U32.is_lt(code,1278))
def deltaBelow521(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow501(code,U32.is_lt(code,1253))
    case False{}: deltaBelow520(code,U32.is_lt(code,1273))
def deltaBelow522(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow523(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow524(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow523(code,U32.is_lt(code,1287))
def deltaBelow525(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow522(code,U32.is_lt(code,1284))
    case False{}: deltaBelow524(code,U32.is_lt(code,1286))
def deltaBelow526(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow527(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow528(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow527(code,U32.is_lt(code,1292))
def deltaBelow529(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow526(code,U32.is_lt(code,1289))
    case False{}: deltaBelow528(code,U32.is_lt(code,1291))
def deltaBelow530(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow525(code,U32.is_lt(code,1285))
    case False{}: deltaBelow529(code,U32.is_lt(code,1290))
def deltaBelow531(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow532(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow533(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow532(code,U32.is_lt(code,1297))
def deltaBelow534(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow531(code,U32.is_lt(code,1294))
    case False{}: deltaBelow533(code,U32.is_lt(code,1296))
def deltaBelow535(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow536(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow537(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow536(code,U32.is_lt(code,1302))
def deltaBelow538(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow535(code,U32.is_lt(code,1299))
    case False{}: deltaBelow537(code,U32.is_lt(code,1301))
def deltaBelow539(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow534(code,U32.is_lt(code,1295))
    case False{}: deltaBelow538(code,U32.is_lt(code,1300))
def deltaBelow540(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow530(code,U32.is_lt(code,1288))
    case False{}: deltaBelow539(code,U32.is_lt(code,1298))
def deltaBelow541(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow542(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow543(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow542(code,U32.is_lt(code,1307))
def deltaBelow544(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow541(code,U32.is_lt(code,1304))
    case False{}: deltaBelow543(code,U32.is_lt(code,1306))
def deltaBelow545(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow546(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow547(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow546(code,U32.is_lt(code,1312))
def deltaBelow548(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow545(code,U32.is_lt(code,1309))
    case False{}: deltaBelow547(code,U32.is_lt(code,1311))
def deltaBelow549(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow544(code,U32.is_lt(code,1305))
    case False{}: deltaBelow548(code,U32.is_lt(code,1310))
def deltaBelow550(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow551(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow552(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow551(code,U32.is_lt(code,1317))
def deltaBelow553(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow550(code,U32.is_lt(code,1314))
    case False{}: deltaBelow552(code,U32.is_lt(code,1316))
def deltaBelow554(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow555(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow554(code,U32.is_lt(code,1320))
def deltaBelow556(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow557(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow556(code,U32.is_lt(code,1323))
def deltaBelow558(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow555(code,U32.is_lt(code,1319))
    case False{}: deltaBelow557(code,U32.is_lt(code,1322))
def deltaBelow559(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow553(code,U32.is_lt(code,1315))
    case False{}: deltaBelow558(code,U32.is_lt(code,1321))
def deltaBelow560(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow549(code,U32.is_lt(code,1308))
    case False{}: deltaBelow559(code,U32.is_lt(code,1318))
def deltaBelow561(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow540(code,U32.is_lt(code,1293))
    case False{}: deltaBelow560(code,U32.is_lt(code,1313))
def deltaBelow562(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow521(code,U32.is_lt(code,1263))
    case False{}: deltaBelow561(code,U32.is_lt(code,1303))
def deltaBelow563(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow564(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 48
def deltaBelow565(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow564(code,U32.is_lt(code,1329))
def deltaBelow566(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow563(code,U32.is_lt(code,1325))
    case False{}: deltaBelow565(code,U32.is_lt(code,1327))
def deltaBelow567(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 7264
def deltaBelow568(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 7264
    case False{}: 0
def deltaBelow569(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow568(code,U32.is_lt(code,4296))
def deltaBelow570(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow567(code,U32.is_lt(code,4256))
    case False{}: deltaBelow569(code,U32.is_lt(code,4295))
def deltaBelow571(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow566(code,U32.is_lt(code,1326))
    case False{}: deltaBelow570(code,U32.is_lt(code,4294))
def deltaBelow572(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 7264
    case False{}: 0
def deltaBelow573(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def deltaBelow574(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 38864
    case False{}: deltaBelow573(code,U32.is_lt(code,5110))
def deltaBelow575(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow572(code,U32.is_lt(code,4302))
    case False{}: deltaBelow574(code,U32.is_lt(code,5104))
def deltaBelow576(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow577(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294964288
def deltaBelow578(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294964288
    case False{}: deltaBelow577(code,U32.is_lt(code,7357))
def deltaBelow579(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow576(code,U32.is_lt(code,7306))
    case False{}: deltaBelow578(code,U32.is_lt(code,7355))
def deltaBelow580(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow575(code,U32.is_lt(code,5024))
    case False{}: deltaBelow579(code,U32.is_lt(code,7312))
def deltaBelow581(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow571(code,U32.is_lt(code,1367))
    case False{}: deltaBelow580(code,U32.is_lt(code,7305))
def deltaBelow582(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow583(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow584(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow583(code,U32.is_lt(code,7683))
def deltaBelow585(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow582(code,U32.is_lt(code,7680))
    case False{}: deltaBelow584(code,U32.is_lt(code,7682))
def deltaBelow586(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow587(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow588(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow587(code,U32.is_lt(code,7688))
def deltaBelow589(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow586(code,U32.is_lt(code,7685))
    case False{}: deltaBelow588(code,U32.is_lt(code,7687))
def deltaBelow590(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow585(code,U32.is_lt(code,7681))
    case False{}: deltaBelow589(code,U32.is_lt(code,7686))
def deltaBelow591(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow592(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow593(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow592(code,U32.is_lt(code,7693))
def deltaBelow594(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow591(code,U32.is_lt(code,7690))
    case False{}: deltaBelow593(code,U32.is_lt(code,7692))
def deltaBelow595(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow596(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow597(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow596(code,U32.is_lt(code,7698))
def deltaBelow598(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow595(code,U32.is_lt(code,7695))
    case False{}: deltaBelow597(code,U32.is_lt(code,7697))
def deltaBelow599(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow594(code,U32.is_lt(code,7691))
    case False{}: deltaBelow598(code,U32.is_lt(code,7696))
def deltaBelow600(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow590(code,U32.is_lt(code,7684))
    case False{}: deltaBelow599(code,U32.is_lt(code,7694))
def deltaBelow601(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow581(code,U32.is_lt(code,4301))
    case False{}: deltaBelow600(code,U32.is_lt(code,7689))
def deltaBelow602(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow603(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow604(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow603(code,U32.is_lt(code,7703))
def deltaBelow605(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow602(code,U32.is_lt(code,7700))
    case False{}: deltaBelow604(code,U32.is_lt(code,7702))
def deltaBelow606(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow607(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow608(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow607(code,U32.is_lt(code,7708))
def deltaBelow609(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow606(code,U32.is_lt(code,7705))
    case False{}: deltaBelow608(code,U32.is_lt(code,7707))
def deltaBelow610(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow605(code,U32.is_lt(code,7701))
    case False{}: deltaBelow609(code,U32.is_lt(code,7706))
def deltaBelow611(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow612(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow613(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow612(code,U32.is_lt(code,7713))
def deltaBelow614(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow611(code,U32.is_lt(code,7710))
    case False{}: deltaBelow613(code,U32.is_lt(code,7712))
def deltaBelow615(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow616(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow617(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow616(code,U32.is_lt(code,7718))
def deltaBelow618(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow615(code,U32.is_lt(code,7715))
    case False{}: deltaBelow617(code,U32.is_lt(code,7717))
def deltaBelow619(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow614(code,U32.is_lt(code,7711))
    case False{}: deltaBelow618(code,U32.is_lt(code,7716))
def deltaBelow620(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow610(code,U32.is_lt(code,7704))
    case False{}: deltaBelow619(code,U32.is_lt(code,7714))
def deltaBelow621(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow622(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow623(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow622(code,U32.is_lt(code,7723))
def deltaBelow624(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow621(code,U32.is_lt(code,7720))
    case False{}: deltaBelow623(code,U32.is_lt(code,7722))
def deltaBelow625(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow626(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow627(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow626(code,U32.is_lt(code,7728))
def deltaBelow628(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow625(code,U32.is_lt(code,7725))
    case False{}: deltaBelow627(code,U32.is_lt(code,7727))
def deltaBelow629(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow624(code,U32.is_lt(code,7721))
    case False{}: deltaBelow628(code,U32.is_lt(code,7726))
def deltaBelow630(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow631(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow632(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow631(code,U32.is_lt(code,7733))
def deltaBelow633(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow630(code,U32.is_lt(code,7730))
    case False{}: deltaBelow632(code,U32.is_lt(code,7732))
def deltaBelow634(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow635(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow634(code,U32.is_lt(code,7736))
def deltaBelow636(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow637(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow636(code,U32.is_lt(code,7739))
def deltaBelow638(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow635(code,U32.is_lt(code,7735))
    case False{}: deltaBelow637(code,U32.is_lt(code,7738))
def deltaBelow639(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow633(code,U32.is_lt(code,7731))
    case False{}: deltaBelow638(code,U32.is_lt(code,7737))
def deltaBelow640(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow629(code,U32.is_lt(code,7724))
    case False{}: deltaBelow639(code,U32.is_lt(code,7734))
def deltaBelow641(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow620(code,U32.is_lt(code,7709))
    case False{}: deltaBelow640(code,U32.is_lt(code,7729))
def deltaBelow642(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow601(code,U32.is_lt(code,7360))
    case False{}: deltaBelow641(code,U32.is_lt(code,7719))
def deltaBelow643(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow562(code,U32.is_lt(code,1283))
    case False{}: deltaBelow642(code,U32.is_lt(code,7699))
def deltaBelow644(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow482(code,U32.is_lt(code,1153))
    case False{}: deltaBelow643(code,U32.is_lt(code,1324))
def deltaBelow645(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow321(code,U32.is_lt(code,420))
    case False{}: deltaBelow644(code,U32.is_lt(code,1243))
def deltaBelow646(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow647(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow648(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow647(code,U32.is_lt(code,7744))
def deltaBelow649(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow646(code,U32.is_lt(code,7741))
    case False{}: deltaBelow648(code,U32.is_lt(code,7743))
def deltaBelow650(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow651(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow652(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow651(code,U32.is_lt(code,7749))
def deltaBelow653(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow650(code,U32.is_lt(code,7746))
    case False{}: deltaBelow652(code,U32.is_lt(code,7748))
def deltaBelow654(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow649(code,U32.is_lt(code,7742))
    case False{}: deltaBelow653(code,U32.is_lt(code,7747))
def deltaBelow655(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow656(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow657(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow656(code,U32.is_lt(code,7754))
def deltaBelow658(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow655(code,U32.is_lt(code,7751))
    case False{}: deltaBelow657(code,U32.is_lt(code,7753))
def deltaBelow659(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow660(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow661(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow660(code,U32.is_lt(code,7759))
def deltaBelow662(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow659(code,U32.is_lt(code,7756))
    case False{}: deltaBelow661(code,U32.is_lt(code,7758))
def deltaBelow663(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow658(code,U32.is_lt(code,7752))
    case False{}: deltaBelow662(code,U32.is_lt(code,7757))
def deltaBelow664(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow654(code,U32.is_lt(code,7745))
    case False{}: deltaBelow663(code,U32.is_lt(code,7755))
def deltaBelow665(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow666(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow667(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow666(code,U32.is_lt(code,7764))
def deltaBelow668(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow665(code,U32.is_lt(code,7761))
    case False{}: deltaBelow667(code,U32.is_lt(code,7763))
def deltaBelow669(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow670(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow671(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow670(code,U32.is_lt(code,7769))
def deltaBelow672(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow669(code,U32.is_lt(code,7766))
    case False{}: deltaBelow671(code,U32.is_lt(code,7768))
def deltaBelow673(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow668(code,U32.is_lt(code,7762))
    case False{}: deltaBelow672(code,U32.is_lt(code,7767))
def deltaBelow674(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow675(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow676(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow675(code,U32.is_lt(code,7774))
def deltaBelow677(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow674(code,U32.is_lt(code,7771))
    case False{}: deltaBelow676(code,U32.is_lt(code,7773))
def deltaBelow678(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow679(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow680(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow679(code,U32.is_lt(code,7779))
def deltaBelow681(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow678(code,U32.is_lt(code,7776))
    case False{}: deltaBelow680(code,U32.is_lt(code,7778))
def deltaBelow682(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow677(code,U32.is_lt(code,7772))
    case False{}: deltaBelow681(code,U32.is_lt(code,7777))
def deltaBelow683(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow673(code,U32.is_lt(code,7765))
    case False{}: deltaBelow682(code,U32.is_lt(code,7775))
def deltaBelow684(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow664(code,U32.is_lt(code,7750))
    case False{}: deltaBelow683(code,U32.is_lt(code,7770))
def deltaBelow685(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow686(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow687(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow686(code,U32.is_lt(code,7784))
def deltaBelow688(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow685(code,U32.is_lt(code,7781))
    case False{}: deltaBelow687(code,U32.is_lt(code,7783))
def deltaBelow689(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow690(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow691(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow690(code,U32.is_lt(code,7789))
def deltaBelow692(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow689(code,U32.is_lt(code,7786))
    case False{}: deltaBelow691(code,U32.is_lt(code,7788))
def deltaBelow693(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow688(code,U32.is_lt(code,7782))
    case False{}: deltaBelow692(code,U32.is_lt(code,7787))
def deltaBelow694(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow695(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow696(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow695(code,U32.is_lt(code,7794))
def deltaBelow697(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow694(code,U32.is_lt(code,7791))
    case False{}: deltaBelow696(code,U32.is_lt(code,7793))
def deltaBelow698(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow699(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow700(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow699(code,U32.is_lt(code,7799))
def deltaBelow701(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow698(code,U32.is_lt(code,7796))
    case False{}: deltaBelow700(code,U32.is_lt(code,7798))
def deltaBelow702(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow697(code,U32.is_lt(code,7792))
    case False{}: deltaBelow701(code,U32.is_lt(code,7797))
def deltaBelow703(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow693(code,U32.is_lt(code,7785))
    case False{}: deltaBelow702(code,U32.is_lt(code,7795))
def deltaBelow704(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow705(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow706(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow705(code,U32.is_lt(code,7804))
def deltaBelow707(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow704(code,U32.is_lt(code,7801))
    case False{}: deltaBelow706(code,U32.is_lt(code,7803))
def deltaBelow708(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow709(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow710(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow709(code,U32.is_lt(code,7809))
def deltaBelow711(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow708(code,U32.is_lt(code,7806))
    case False{}: deltaBelow710(code,U32.is_lt(code,7808))
def deltaBelow712(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow707(code,U32.is_lt(code,7802))
    case False{}: deltaBelow711(code,U32.is_lt(code,7807))
def deltaBelow713(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow714(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow715(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow714(code,U32.is_lt(code,7814))
def deltaBelow716(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow713(code,U32.is_lt(code,7811))
    case False{}: deltaBelow715(code,U32.is_lt(code,7813))
def deltaBelow717(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow718(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow717(code,U32.is_lt(code,7817))
def deltaBelow719(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow720(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow719(code,U32.is_lt(code,7820))
def deltaBelow721(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow718(code,U32.is_lt(code,7816))
    case False{}: deltaBelow720(code,U32.is_lt(code,7819))
def deltaBelow722(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow716(code,U32.is_lt(code,7812))
    case False{}: deltaBelow721(code,U32.is_lt(code,7818))
def deltaBelow723(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow712(code,U32.is_lt(code,7805))
    case False{}: deltaBelow722(code,U32.is_lt(code,7815))
def deltaBelow724(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow703(code,U32.is_lt(code,7790))
    case False{}: deltaBelow723(code,U32.is_lt(code,7810))
def deltaBelow725(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow684(code,U32.is_lt(code,7760))
    case False{}: deltaBelow724(code,U32.is_lt(code,7800))
def deltaBelow726(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow727(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow728(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow727(code,U32.is_lt(code,7825))
def deltaBelow729(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow726(code,U32.is_lt(code,7822))
    case False{}: deltaBelow728(code,U32.is_lt(code,7824))
def deltaBelow730(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow731(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294959681
def deltaBelow732(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow731(code,U32.is_lt(code,7838))
def deltaBelow733(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow730(code,U32.is_lt(code,7827))
    case False{}: deltaBelow732(code,U32.is_lt(code,7829))
def deltaBelow734(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow729(code,U32.is_lt(code,7823))
    case False{}: deltaBelow733(code,U32.is_lt(code,7828))
def deltaBelow735(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow736(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow737(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow736(code,U32.is_lt(code,7843))
def deltaBelow738(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow735(code,U32.is_lt(code,7840))
    case False{}: deltaBelow737(code,U32.is_lt(code,7842))
def deltaBelow739(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow740(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow741(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow740(code,U32.is_lt(code,7848))
def deltaBelow742(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow739(code,U32.is_lt(code,7845))
    case False{}: deltaBelow741(code,U32.is_lt(code,7847))
def deltaBelow743(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow738(code,U32.is_lt(code,7841))
    case False{}: deltaBelow742(code,U32.is_lt(code,7846))
def deltaBelow744(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow734(code,U32.is_lt(code,7826))
    case False{}: deltaBelow743(code,U32.is_lt(code,7844))
def deltaBelow745(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow746(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow747(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow746(code,U32.is_lt(code,7853))
def deltaBelow748(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow745(code,U32.is_lt(code,7850))
    case False{}: deltaBelow747(code,U32.is_lt(code,7852))
def deltaBelow749(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow750(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow751(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow750(code,U32.is_lt(code,7858))
def deltaBelow752(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow749(code,U32.is_lt(code,7855))
    case False{}: deltaBelow751(code,U32.is_lt(code,7857))
def deltaBelow753(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow748(code,U32.is_lt(code,7851))
    case False{}: deltaBelow752(code,U32.is_lt(code,7856))
def deltaBelow754(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow755(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow756(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow755(code,U32.is_lt(code,7863))
def deltaBelow757(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow754(code,U32.is_lt(code,7860))
    case False{}: deltaBelow756(code,U32.is_lt(code,7862))
def deltaBelow758(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow759(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow760(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow759(code,U32.is_lt(code,7868))
def deltaBelow761(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow758(code,U32.is_lt(code,7865))
    case False{}: deltaBelow760(code,U32.is_lt(code,7867))
def deltaBelow762(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow757(code,U32.is_lt(code,7861))
    case False{}: deltaBelow761(code,U32.is_lt(code,7866))
def deltaBelow763(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow753(code,U32.is_lt(code,7854))
    case False{}: deltaBelow762(code,U32.is_lt(code,7864))
def deltaBelow764(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow744(code,U32.is_lt(code,7839))
    case False{}: deltaBelow763(code,U32.is_lt(code,7859))
def deltaBelow765(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow766(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow767(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow766(code,U32.is_lt(code,7873))
def deltaBelow768(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow765(code,U32.is_lt(code,7870))
    case False{}: deltaBelow767(code,U32.is_lt(code,7872))
def deltaBelow769(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow770(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow771(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow770(code,U32.is_lt(code,7878))
def deltaBelow772(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow769(code,U32.is_lt(code,7875))
    case False{}: deltaBelow771(code,U32.is_lt(code,7877))
def deltaBelow773(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow768(code,U32.is_lt(code,7871))
    case False{}: deltaBelow772(code,U32.is_lt(code,7876))
def deltaBelow774(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow775(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow776(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow775(code,U32.is_lt(code,7883))
def deltaBelow777(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow774(code,U32.is_lt(code,7880))
    case False{}: deltaBelow776(code,U32.is_lt(code,7882))
def deltaBelow778(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow779(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow780(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow779(code,U32.is_lt(code,7888))
def deltaBelow781(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow778(code,U32.is_lt(code,7885))
    case False{}: deltaBelow780(code,U32.is_lt(code,7887))
def deltaBelow782(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow777(code,U32.is_lt(code,7881))
    case False{}: deltaBelow781(code,U32.is_lt(code,7886))
def deltaBelow783(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow773(code,U32.is_lt(code,7874))
    case False{}: deltaBelow782(code,U32.is_lt(code,7884))
def deltaBelow784(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow785(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow786(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow785(code,U32.is_lt(code,7893))
def deltaBelow787(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow784(code,U32.is_lt(code,7890))
    case False{}: deltaBelow786(code,U32.is_lt(code,7892))
def deltaBelow788(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow789(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow790(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow789(code,U32.is_lt(code,7898))
def deltaBelow791(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow788(code,U32.is_lt(code,7895))
    case False{}: deltaBelow790(code,U32.is_lt(code,7897))
def deltaBelow792(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow787(code,U32.is_lt(code,7891))
    case False{}: deltaBelow791(code,U32.is_lt(code,7896))
def deltaBelow793(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow794(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow795(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow794(code,U32.is_lt(code,7903))
def deltaBelow796(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow793(code,U32.is_lt(code,7900))
    case False{}: deltaBelow795(code,U32.is_lt(code,7902))
def deltaBelow797(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow798(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow797(code,U32.is_lt(code,7906))
def deltaBelow799(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow800(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow799(code,U32.is_lt(code,7909))
def deltaBelow801(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow798(code,U32.is_lt(code,7905))
    case False{}: deltaBelow800(code,U32.is_lt(code,7908))
def deltaBelow802(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow796(code,U32.is_lt(code,7901))
    case False{}: deltaBelow801(code,U32.is_lt(code,7907))
def deltaBelow803(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow792(code,U32.is_lt(code,7894))
    case False{}: deltaBelow802(code,U32.is_lt(code,7904))
def deltaBelow804(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow783(code,U32.is_lt(code,7879))
    case False{}: deltaBelow803(code,U32.is_lt(code,7899))
def deltaBelow805(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow764(code,U32.is_lt(code,7849))
    case False{}: deltaBelow804(code,U32.is_lt(code,7889))
def deltaBelow806(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow725(code,U32.is_lt(code,7780))
    case False{}: deltaBelow805(code,U32.is_lt(code,7869))
def deltaBelow807(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow808(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow809(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow808(code,U32.is_lt(code,7914))
def deltaBelow810(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow807(code,U32.is_lt(code,7911))
    case False{}: deltaBelow809(code,U32.is_lt(code,7913))
def deltaBelow811(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow812(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow813(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow812(code,U32.is_lt(code,7919))
def deltaBelow814(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow811(code,U32.is_lt(code,7916))
    case False{}: deltaBelow813(code,U32.is_lt(code,7918))
def deltaBelow815(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow810(code,U32.is_lt(code,7912))
    case False{}: deltaBelow814(code,U32.is_lt(code,7917))
def deltaBelow816(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow817(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow818(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow817(code,U32.is_lt(code,7924))
def deltaBelow819(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow816(code,U32.is_lt(code,7921))
    case False{}: deltaBelow818(code,U32.is_lt(code,7923))
def deltaBelow820(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow821(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow822(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow821(code,U32.is_lt(code,7929))
def deltaBelow823(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow820(code,U32.is_lt(code,7926))
    case False{}: deltaBelow822(code,U32.is_lt(code,7928))
def deltaBelow824(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow819(code,U32.is_lt(code,7922))
    case False{}: deltaBelow823(code,U32.is_lt(code,7927))
def deltaBelow825(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow815(code,U32.is_lt(code,7915))
    case False{}: deltaBelow824(code,U32.is_lt(code,7925))
def deltaBelow826(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow827(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow828(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow827(code,U32.is_lt(code,7934))
def deltaBelow829(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow826(code,U32.is_lt(code,7931))
    case False{}: deltaBelow828(code,U32.is_lt(code,7933))
def deltaBelow830(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967288
def deltaBelow831(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: 0
def deltaBelow832(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow831(code,U32.is_lt(code,7966))
def deltaBelow833(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow830(code,U32.is_lt(code,7944))
    case False{}: deltaBelow832(code,U32.is_lt(code,7960))
def deltaBelow834(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow829(code,U32.is_lt(code,7932))
    case False{}: deltaBelow833(code,U32.is_lt(code,7952))
def deltaBelow835(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: 0
def deltaBelow836(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967288
def deltaBelow837(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: deltaBelow836(code,U32.is_lt(code,8008))
def deltaBelow838(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow835(code,U32.is_lt(code,7984))
    case False{}: deltaBelow837(code,U32.is_lt(code,8000))
def deltaBelow839(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967288
def deltaBelow840(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: 0
def deltaBelow841(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow840(code,U32.is_lt(code,8028))
def deltaBelow842(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow839(code,U32.is_lt(code,8025))
    case False{}: deltaBelow841(code,U32.is_lt(code,8027))
def deltaBelow843(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow838(code,U32.is_lt(code,7992))
    case False{}: deltaBelow842(code,U32.is_lt(code,8026))
def deltaBelow844(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow834(code,U32.is_lt(code,7935))
    case False{}: deltaBelow843(code,U32.is_lt(code,8014))
def deltaBelow845(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow825(code,U32.is_lt(code,7920))
    case False{}: deltaBelow844(code,U32.is_lt(code,7976))
def deltaBelow846(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: 0
def deltaBelow847(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967288
def deltaBelow848(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: deltaBelow847(code,U32.is_lt(code,8040))
def deltaBelow849(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow846(code,U32.is_lt(code,8030))
    case False{}: deltaBelow848(code,U32.is_lt(code,8032))
def deltaBelow850(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967288
def deltaBelow851(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: 0
def deltaBelow852(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow851(code,U32.is_lt(code,8096))
def deltaBelow853(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow850(code,U32.is_lt(code,8072))
    case False{}: deltaBelow852(code,U32.is_lt(code,8088))
def deltaBelow854(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow849(code,U32.is_lt(code,8031))
    case False{}: deltaBelow853(code,U32.is_lt(code,8080))
def deltaBelow855(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: 0
def deltaBelow856(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967222
    case False{}: 4294967287
def deltaBelow857(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: deltaBelow856(code,U32.is_lt(code,8124))
def deltaBelow858(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow855(code,U32.is_lt(code,8112))
    case False{}: deltaBelow857(code,U32.is_lt(code,8122))
def deltaBelow859(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967210
def deltaBelow860(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967288
def deltaBelow861(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967287
    case False{}: deltaBelow860(code,U32.is_lt(code,8152))
def deltaBelow862(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow859(code,U32.is_lt(code,8136))
    case False{}: deltaBelow861(code,U32.is_lt(code,8141))
def deltaBelow863(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow858(code,U32.is_lt(code,8120))
    case False{}: deltaBelow862(code,U32.is_lt(code,8140))
def deltaBelow864(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow854(code,U32.is_lt(code,8048))
    case False{}: deltaBelow863(code,U32.is_lt(code,8125))
def deltaBelow865(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967196
    case False{}: 0
def deltaBelow866(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967184
    case False{}: 4294967289
def deltaBelow867(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967288
    case False{}: deltaBelow866(code,U32.is_lt(code,8172))
def deltaBelow868(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow865(code,U32.is_lt(code,8156))
    case False{}: deltaBelow867(code,U32.is_lt(code,8170))
def deltaBelow869(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294967168
def deltaBelow870(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967287
    case False{}: 0
def deltaBelow871(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967170
    case False{}: deltaBelow870(code,U32.is_lt(code,8189))
def deltaBelow872(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow869(code,U32.is_lt(code,8184))
    case False{}: deltaBelow871(code,U32.is_lt(code,8188))
def deltaBelow873(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow868(code,U32.is_lt(code,8168))
    case False{}: deltaBelow872(code,U32.is_lt(code,8186))
def deltaBelow874(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294959779
    case False{}: 0
def deltaBelow875(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294959034
    case False{}: 0
def deltaBelow876(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294958913
    case False{}: deltaBelow875(code,U32.is_lt(code,8492))
def deltaBelow877(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow874(code,U32.is_lt(code,8487))
    case False{}: deltaBelow876(code,U32.is_lt(code,8491))
def deltaBelow878(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 16
def deltaBelow879(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 28
    case False{}: deltaBelow878(code,U32.is_lt(code,8544))
def deltaBelow880(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow881(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow880(code,U32.is_lt(code,8580))
def deltaBelow882(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow879(code,U32.is_lt(code,8499))
    case False{}: deltaBelow881(code,U32.is_lt(code,8579))
def deltaBelow883(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow877(code,U32.is_lt(code,8490))
    case False{}: deltaBelow882(code,U32.is_lt(code,8560))
def deltaBelow884(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow873(code,U32.is_lt(code,8173))
    case False{}: deltaBelow883(code,U32.is_lt(code,8498))
def deltaBelow885(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow864(code,U32.is_lt(code,8104))
    case False{}: deltaBelow884(code,U32.is_lt(code,8486))
def deltaBelow886(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow845(code,U32.is_lt(code,7930))
    case False{}: deltaBelow885(code,U32.is_lt(code,8154))
def deltaBelow887(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 26
    case False{}: 0
def deltaBelow888(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow889(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 48
    case False{}: deltaBelow888(code,U32.is_lt(code,11360))
def deltaBelow890(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow887(code,U32.is_lt(code,9424))
    case False{}: deltaBelow889(code,U32.is_lt(code,11312))
def deltaBelow891(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294956553
def deltaBelow892(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294956569
    case False{}: 0
def deltaBelow893(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294963482
    case False{}: deltaBelow892(code,U32.is_lt(code,11365))
def deltaBelow894(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow891(code,U32.is_lt(code,11362))
    case False{}: deltaBelow893(code,U32.is_lt(code,11364))
def deltaBelow895(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow890(code,U32.is_lt(code,11264))
    case False{}: deltaBelow894(code,U32.is_lt(code,11363))
def deltaBelow896(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow897(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow898(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow897(code,U32.is_lt(code,11371))
def deltaBelow899(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow896(code,U32.is_lt(code,11368))
    case False{}: deltaBelow898(code,U32.is_lt(code,11370))
def deltaBelow900(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294956516
def deltaBelow901(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294956513
    case False{}: 4294956514
def deltaBelow902(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294956547
    case False{}: deltaBelow901(code,U32.is_lt(code,11376))
def deltaBelow903(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow900(code,U32.is_lt(code,11373))
    case False{}: deltaBelow902(code,U32.is_lt(code,11375))
def deltaBelow904(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow899(code,U32.is_lt(code,11369))
    case False{}: deltaBelow903(code,U32.is_lt(code,11374))
def deltaBelow905(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow895(code,U32.is_lt(code,11361))
    case False{}: deltaBelow904(code,U32.is_lt(code,11372))
def deltaBelow906(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow907(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow908(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow907(code,U32.is_lt(code,11382))
def deltaBelow909(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow906(code,U32.is_lt(code,11378))
    case False{}: deltaBelow908(code,U32.is_lt(code,11381))
def deltaBelow910(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294956481
    case False{}: 1
def deltaBelow911(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow912(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow911(code,U32.is_lt(code,11395))
def deltaBelow913(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow910(code,U32.is_lt(code,11392))
    case False{}: deltaBelow912(code,U32.is_lt(code,11394))
def deltaBelow914(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow909(code,U32.is_lt(code,11379))
    case False{}: deltaBelow913(code,U32.is_lt(code,11393))
def deltaBelow915(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow916(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow917(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow916(code,U32.is_lt(code,11400))
def deltaBelow918(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow915(code,U32.is_lt(code,11397))
    case False{}: deltaBelow917(code,U32.is_lt(code,11399))
def deltaBelow919(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow920(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow921(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow920(code,U32.is_lt(code,11405))
def deltaBelow922(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow919(code,U32.is_lt(code,11402))
    case False{}: deltaBelow921(code,U32.is_lt(code,11404))
def deltaBelow923(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow918(code,U32.is_lt(code,11398))
    case False{}: deltaBelow922(code,U32.is_lt(code,11403))
def deltaBelow924(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow914(code,U32.is_lt(code,11390))
    case False{}: deltaBelow923(code,U32.is_lt(code,11401))
def deltaBelow925(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow905(code,U32.is_lt(code,11367))
    case False{}: deltaBelow924(code,U32.is_lt(code,11396))
def deltaBelow926(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow927(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow928(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow927(code,U32.is_lt(code,11410))
def deltaBelow929(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow926(code,U32.is_lt(code,11407))
    case False{}: deltaBelow928(code,U32.is_lt(code,11409))
def deltaBelow930(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow931(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow932(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow931(code,U32.is_lt(code,11415))
def deltaBelow933(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow930(code,U32.is_lt(code,11412))
    case False{}: deltaBelow932(code,U32.is_lt(code,11414))
def deltaBelow934(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow929(code,U32.is_lt(code,11408))
    case False{}: deltaBelow933(code,U32.is_lt(code,11413))
def deltaBelow935(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow936(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow937(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow936(code,U32.is_lt(code,11420))
def deltaBelow938(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow935(code,U32.is_lt(code,11417))
    case False{}: deltaBelow937(code,U32.is_lt(code,11419))
def deltaBelow939(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow940(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow941(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow940(code,U32.is_lt(code,11425))
def deltaBelow942(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow939(code,U32.is_lt(code,11422))
    case False{}: deltaBelow941(code,U32.is_lt(code,11424))
def deltaBelow943(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow938(code,U32.is_lt(code,11418))
    case False{}: deltaBelow942(code,U32.is_lt(code,11423))
def deltaBelow944(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow934(code,U32.is_lt(code,11411))
    case False{}: deltaBelow943(code,U32.is_lt(code,11421))
def deltaBelow945(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow946(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow947(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow946(code,U32.is_lt(code,11430))
def deltaBelow948(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow945(code,U32.is_lt(code,11427))
    case False{}: deltaBelow947(code,U32.is_lt(code,11429))
def deltaBelow949(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow950(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow951(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow950(code,U32.is_lt(code,11435))
def deltaBelow952(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow949(code,U32.is_lt(code,11432))
    case False{}: deltaBelow951(code,U32.is_lt(code,11434))
def deltaBelow953(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow948(code,U32.is_lt(code,11428))
    case False{}: deltaBelow952(code,U32.is_lt(code,11433))
def deltaBelow954(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow955(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow956(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow955(code,U32.is_lt(code,11440))
def deltaBelow957(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow954(code,U32.is_lt(code,11437))
    case False{}: deltaBelow956(code,U32.is_lt(code,11439))
def deltaBelow958(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow959(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow958(code,U32.is_lt(code,11443))
def deltaBelow960(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow961(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow960(code,U32.is_lt(code,11446))
def deltaBelow962(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow959(code,U32.is_lt(code,11442))
    case False{}: deltaBelow961(code,U32.is_lt(code,11445))
def deltaBelow963(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow957(code,U32.is_lt(code,11438))
    case False{}: deltaBelow962(code,U32.is_lt(code,11444))
def deltaBelow964(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow953(code,U32.is_lt(code,11431))
    case False{}: deltaBelow963(code,U32.is_lt(code,11441))
def deltaBelow965(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow944(code,U32.is_lt(code,11416))
    case False{}: deltaBelow964(code,U32.is_lt(code,11436))
def deltaBelow966(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow925(code,U32.is_lt(code,11377))
    case False{}: deltaBelow965(code,U32.is_lt(code,11426))
def deltaBelow967(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow886(code,U32.is_lt(code,8029))
    case False{}: deltaBelow966(code,U32.is_lt(code,11406))
def deltaBelow968(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow806(code,U32.is_lt(code,7821))
    case False{}: deltaBelow967(code,U32.is_lt(code,9398))
def deltaBelow969(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow970(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow971(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow970(code,U32.is_lt(code,11451))
def deltaBelow972(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow969(code,U32.is_lt(code,11448))
    case False{}: deltaBelow971(code,U32.is_lt(code,11450))
def deltaBelow973(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow974(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow975(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow974(code,U32.is_lt(code,11456))
def deltaBelow976(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow973(code,U32.is_lt(code,11453))
    case False{}: deltaBelow975(code,U32.is_lt(code,11455))
def deltaBelow977(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow972(code,U32.is_lt(code,11449))
    case False{}: deltaBelow976(code,U32.is_lt(code,11454))
def deltaBelow978(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow979(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow980(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow979(code,U32.is_lt(code,11461))
def deltaBelow981(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow978(code,U32.is_lt(code,11458))
    case False{}: deltaBelow980(code,U32.is_lt(code,11460))
def deltaBelow982(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow983(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow984(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow983(code,U32.is_lt(code,11466))
def deltaBelow985(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow982(code,U32.is_lt(code,11463))
    case False{}: deltaBelow984(code,U32.is_lt(code,11465))
def deltaBelow986(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow981(code,U32.is_lt(code,11459))
    case False{}: deltaBelow985(code,U32.is_lt(code,11464))
def deltaBelow987(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow977(code,U32.is_lt(code,11452))
    case False{}: deltaBelow986(code,U32.is_lt(code,11462))
def deltaBelow988(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow989(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow990(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow989(code,U32.is_lt(code,11471))
def deltaBelow991(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow988(code,U32.is_lt(code,11468))
    case False{}: deltaBelow990(code,U32.is_lt(code,11470))
def deltaBelow992(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow993(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow994(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow993(code,U32.is_lt(code,11476))
def deltaBelow995(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow992(code,U32.is_lt(code,11473))
    case False{}: deltaBelow994(code,U32.is_lt(code,11475))
def deltaBelow996(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow991(code,U32.is_lt(code,11469))
    case False{}: deltaBelow995(code,U32.is_lt(code,11474))
def deltaBelow997(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow998(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow999(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow998(code,U32.is_lt(code,11481))
def deltaBelow1000(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow997(code,U32.is_lt(code,11478))
    case False{}: deltaBelow999(code,U32.is_lt(code,11480))
def deltaBelow1001(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1002(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1003(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1002(code,U32.is_lt(code,11486))
def deltaBelow1004(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1001(code,U32.is_lt(code,11483))
    case False{}: deltaBelow1003(code,U32.is_lt(code,11485))
def deltaBelow1005(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1000(code,U32.is_lt(code,11479))
    case False{}: deltaBelow1004(code,U32.is_lt(code,11484))
def deltaBelow1006(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow996(code,U32.is_lt(code,11472))
    case False{}: deltaBelow1005(code,U32.is_lt(code,11482))
def deltaBelow1007(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow987(code,U32.is_lt(code,11457))
    case False{}: deltaBelow1006(code,U32.is_lt(code,11477))
def deltaBelow1008(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1009(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1010(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1009(code,U32.is_lt(code,11491))
def deltaBelow1011(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1008(code,U32.is_lt(code,11488))
    case False{}: deltaBelow1010(code,U32.is_lt(code,11490))
def deltaBelow1012(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1013(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1014(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1013(code,U32.is_lt(code,11506))
def deltaBelow1015(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1012(code,U32.is_lt(code,11500))
    case False{}: deltaBelow1014(code,U32.is_lt(code,11502))
def deltaBelow1016(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1011(code,U32.is_lt(code,11489))
    case False{}: deltaBelow1015(code,U32.is_lt(code,11501))
def deltaBelow1017(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1018(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1019(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1018(code,U32.is_lt(code,42563))
def deltaBelow1020(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1017(code,U32.is_lt(code,42560))
    case False{}: deltaBelow1019(code,U32.is_lt(code,42562))
def deltaBelow1021(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1022(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1023(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1022(code,U32.is_lt(code,42568))
def deltaBelow1024(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1021(code,U32.is_lt(code,42565))
    case False{}: deltaBelow1023(code,U32.is_lt(code,42567))
def deltaBelow1025(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1020(code,U32.is_lt(code,42561))
    case False{}: deltaBelow1024(code,U32.is_lt(code,42566))
def deltaBelow1026(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1016(code,U32.is_lt(code,11499))
    case False{}: deltaBelow1025(code,U32.is_lt(code,42564))
def deltaBelow1027(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1028(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1029(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1028(code,U32.is_lt(code,42573))
def deltaBelow1030(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1027(code,U32.is_lt(code,42570))
    case False{}: deltaBelow1029(code,U32.is_lt(code,42572))
def deltaBelow1031(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1032(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1033(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1032(code,U32.is_lt(code,42578))
def deltaBelow1034(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1031(code,U32.is_lt(code,42575))
    case False{}: deltaBelow1033(code,U32.is_lt(code,42577))
def deltaBelow1035(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1030(code,U32.is_lt(code,42571))
    case False{}: deltaBelow1034(code,U32.is_lt(code,42576))
def deltaBelow1036(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1037(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1038(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1037(code,U32.is_lt(code,42583))
def deltaBelow1039(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1036(code,U32.is_lt(code,42580))
    case False{}: deltaBelow1038(code,U32.is_lt(code,42582))
def deltaBelow1040(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1041(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1040(code,U32.is_lt(code,42586))
def deltaBelow1042(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1043(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1042(code,U32.is_lt(code,42589))
def deltaBelow1044(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1041(code,U32.is_lt(code,42585))
    case False{}: deltaBelow1043(code,U32.is_lt(code,42588))
def deltaBelow1045(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1039(code,U32.is_lt(code,42581))
    case False{}: deltaBelow1044(code,U32.is_lt(code,42587))
def deltaBelow1046(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1035(code,U32.is_lt(code,42574))
    case False{}: deltaBelow1045(code,U32.is_lt(code,42584))
def deltaBelow1047(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1026(code,U32.is_lt(code,11507))
    case False{}: deltaBelow1046(code,U32.is_lt(code,42579))
def deltaBelow1048(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1007(code,U32.is_lt(code,11467))
    case False{}: deltaBelow1047(code,U32.is_lt(code,42569))
def deltaBelow1049(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1050(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1051(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1050(code,U32.is_lt(code,42594))
def deltaBelow1052(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1049(code,U32.is_lt(code,42591))
    case False{}: deltaBelow1051(code,U32.is_lt(code,42593))
def deltaBelow1053(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1054(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1055(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1054(code,U32.is_lt(code,42599))
def deltaBelow1056(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1053(code,U32.is_lt(code,42596))
    case False{}: deltaBelow1055(code,U32.is_lt(code,42598))
def deltaBelow1057(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1052(code,U32.is_lt(code,42592))
    case False{}: deltaBelow1056(code,U32.is_lt(code,42597))
def deltaBelow1058(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1059(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1060(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1059(code,U32.is_lt(code,42604))
def deltaBelow1061(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1058(code,U32.is_lt(code,42601))
    case False{}: deltaBelow1060(code,U32.is_lt(code,42603))
def deltaBelow1062(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1063(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1064(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1063(code,U32.is_lt(code,42627))
def deltaBelow1065(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1062(code,U32.is_lt(code,42624))
    case False{}: deltaBelow1064(code,U32.is_lt(code,42626))
def deltaBelow1066(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1061(code,U32.is_lt(code,42602))
    case False{}: deltaBelow1065(code,U32.is_lt(code,42625))
def deltaBelow1067(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1057(code,U32.is_lt(code,42595))
    case False{}: deltaBelow1066(code,U32.is_lt(code,42605))
def deltaBelow1068(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1069(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1070(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1069(code,U32.is_lt(code,42632))
def deltaBelow1071(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1068(code,U32.is_lt(code,42629))
    case False{}: deltaBelow1070(code,U32.is_lt(code,42631))
def deltaBelow1072(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1073(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1074(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1073(code,U32.is_lt(code,42637))
def deltaBelow1075(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1072(code,U32.is_lt(code,42634))
    case False{}: deltaBelow1074(code,U32.is_lt(code,42636))
def deltaBelow1076(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1071(code,U32.is_lt(code,42630))
    case False{}: deltaBelow1075(code,U32.is_lt(code,42635))
def deltaBelow1077(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1078(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1079(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1078(code,U32.is_lt(code,42642))
def deltaBelow1080(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1077(code,U32.is_lt(code,42639))
    case False{}: deltaBelow1079(code,U32.is_lt(code,42641))
def deltaBelow1081(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1082(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1083(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1082(code,U32.is_lt(code,42647))
def deltaBelow1084(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1081(code,U32.is_lt(code,42644))
    case False{}: deltaBelow1083(code,U32.is_lt(code,42646))
def deltaBelow1085(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1080(code,U32.is_lt(code,42640))
    case False{}: deltaBelow1084(code,U32.is_lt(code,42645))
def deltaBelow1086(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1076(code,U32.is_lt(code,42633))
    case False{}: deltaBelow1085(code,U32.is_lt(code,42643))
def deltaBelow1087(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1067(code,U32.is_lt(code,42600))
    case False{}: deltaBelow1086(code,U32.is_lt(code,42638))
def deltaBelow1088(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1089(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1090(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1089(code,U32.is_lt(code,42786))
def deltaBelow1091(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1088(code,U32.is_lt(code,42649))
    case False{}: deltaBelow1090(code,U32.is_lt(code,42651))
def deltaBelow1092(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1093(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1094(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1093(code,U32.is_lt(code,42791))
def deltaBelow1095(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1092(code,U32.is_lt(code,42788))
    case False{}: deltaBelow1094(code,U32.is_lt(code,42790))
def deltaBelow1096(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1091(code,U32.is_lt(code,42650))
    case False{}: deltaBelow1095(code,U32.is_lt(code,42789))
def deltaBelow1097(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1098(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1099(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1098(code,U32.is_lt(code,42796))
def deltaBelow1100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1097(code,U32.is_lt(code,42793))
    case False{}: deltaBelow1099(code,U32.is_lt(code,42795))
def deltaBelow1101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1102(code,U32.is_lt(code,42803))
def deltaBelow1104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1101(code,U32.is_lt(code,42798))
    case False{}: deltaBelow1103(code,U32.is_lt(code,42802))
def deltaBelow1105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1100(code,U32.is_lt(code,42794))
    case False{}: deltaBelow1104(code,U32.is_lt(code,42799))
def deltaBelow1106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1096(code,U32.is_lt(code,42787))
    case False{}: deltaBelow1105(code,U32.is_lt(code,42797))
def deltaBelow1107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1108(code,U32.is_lt(code,42808))
def deltaBelow1110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1107(code,U32.is_lt(code,42805))
    case False{}: deltaBelow1109(code,U32.is_lt(code,42807))
def deltaBelow1111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1112(code,U32.is_lt(code,42813))
def deltaBelow1114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1111(code,U32.is_lt(code,42810))
    case False{}: deltaBelow1113(code,U32.is_lt(code,42812))
def deltaBelow1115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1110(code,U32.is_lt(code,42806))
    case False{}: deltaBelow1114(code,U32.is_lt(code,42811))
def deltaBelow1116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1117(code,U32.is_lt(code,42818))
def deltaBelow1119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1116(code,U32.is_lt(code,42815))
    case False{}: deltaBelow1118(code,U32.is_lt(code,42817))
def deltaBelow1120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1120(code,U32.is_lt(code,42821))
def deltaBelow1122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1122(code,U32.is_lt(code,42824))
def deltaBelow1124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1121(code,U32.is_lt(code,42820))
    case False{}: deltaBelow1123(code,U32.is_lt(code,42823))
def deltaBelow1125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1119(code,U32.is_lt(code,42816))
    case False{}: deltaBelow1124(code,U32.is_lt(code,42822))
def deltaBelow1126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1115(code,U32.is_lt(code,42809))
    case False{}: deltaBelow1125(code,U32.is_lt(code,42819))
def deltaBelow1127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1106(code,U32.is_lt(code,42792))
    case False{}: deltaBelow1126(code,U32.is_lt(code,42814))
def deltaBelow1128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1087(code,U32.is_lt(code,42628))
    case False{}: deltaBelow1127(code,U32.is_lt(code,42804))
def deltaBelow1129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1048(code,U32.is_lt(code,11487))
    case False{}: deltaBelow1128(code,U32.is_lt(code,42648))
def deltaBelow1130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1131(code,U32.is_lt(code,42829))
def deltaBelow1133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1130(code,U32.is_lt(code,42826))
    case False{}: deltaBelow1132(code,U32.is_lt(code,42828))
def deltaBelow1134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1135(code,U32.is_lt(code,42834))
def deltaBelow1137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1134(code,U32.is_lt(code,42831))
    case False{}: deltaBelow1136(code,U32.is_lt(code,42833))
def deltaBelow1138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1133(code,U32.is_lt(code,42827))
    case False{}: deltaBelow1137(code,U32.is_lt(code,42832))
def deltaBelow1139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1140(code,U32.is_lt(code,42839))
def deltaBelow1142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1139(code,U32.is_lt(code,42836))
    case False{}: deltaBelow1141(code,U32.is_lt(code,42838))
def deltaBelow1143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1144(code,U32.is_lt(code,42844))
def deltaBelow1146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1143(code,U32.is_lt(code,42841))
    case False{}: deltaBelow1145(code,U32.is_lt(code,42843))
def deltaBelow1147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1142(code,U32.is_lt(code,42837))
    case False{}: deltaBelow1146(code,U32.is_lt(code,42842))
def deltaBelow1148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1138(code,U32.is_lt(code,42830))
    case False{}: deltaBelow1147(code,U32.is_lt(code,42840))
def deltaBelow1149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1150(code,U32.is_lt(code,42849))
def deltaBelow1152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1149(code,U32.is_lt(code,42846))
    case False{}: deltaBelow1151(code,U32.is_lt(code,42848))
def deltaBelow1153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1154(code,U32.is_lt(code,42854))
def deltaBelow1156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1153(code,U32.is_lt(code,42851))
    case False{}: deltaBelow1155(code,U32.is_lt(code,42853))
def deltaBelow1157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1152(code,U32.is_lt(code,42847))
    case False{}: deltaBelow1156(code,U32.is_lt(code,42852))
def deltaBelow1158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1159(code,U32.is_lt(code,42859))
def deltaBelow1161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1158(code,U32.is_lt(code,42856))
    case False{}: deltaBelow1160(code,U32.is_lt(code,42858))
def deltaBelow1162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1163(code,U32.is_lt(code,42873))
def deltaBelow1165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1162(code,U32.is_lt(code,42861))
    case False{}: deltaBelow1164(code,U32.is_lt(code,42863))
def deltaBelow1166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1161(code,U32.is_lt(code,42857))
    case False{}: deltaBelow1165(code,U32.is_lt(code,42862))
def deltaBelow1167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1157(code,U32.is_lt(code,42850))
    case False{}: deltaBelow1166(code,U32.is_lt(code,42860))
def deltaBelow1168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1148(code,U32.is_lt(code,42835))
    case False{}: deltaBelow1167(code,U32.is_lt(code,42855))
def deltaBelow1169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294931964
    case False{}: 1
def deltaBelow1171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1170(code,U32.is_lt(code,42878))
def deltaBelow1172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1169(code,U32.is_lt(code,42875))
    case False{}: deltaBelow1171(code,U32.is_lt(code,42877))
def deltaBelow1173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1174(code,U32.is_lt(code,42883))
def deltaBelow1176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1173(code,U32.is_lt(code,42880))
    case False{}: deltaBelow1175(code,U32.is_lt(code,42882))
def deltaBelow1177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1172(code,U32.is_lt(code,42876))
    case False{}: deltaBelow1176(code,U32.is_lt(code,42881))
def deltaBelow1178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1179(code,U32.is_lt(code,42891))
def deltaBelow1181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1178(code,U32.is_lt(code,42885))
    case False{}: deltaBelow1180(code,U32.is_lt(code,42887))
def deltaBelow1182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294925016
def deltaBelow1183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1183(code,U32.is_lt(code,42897))
def deltaBelow1185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1182(code,U32.is_lt(code,42893))
    case False{}: deltaBelow1184(code,U32.is_lt(code,42896))
def deltaBelow1186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1181(code,U32.is_lt(code,42886))
    case False{}: deltaBelow1185(code,U32.is_lt(code,42894))
def deltaBelow1187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1177(code,U32.is_lt(code,42879))
    case False{}: deltaBelow1186(code,U32.is_lt(code,42892))
def deltaBelow1188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1189(code,U32.is_lt(code,42904))
def deltaBelow1191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1188(code,U32.is_lt(code,42899))
    case False{}: deltaBelow1190(code,U32.is_lt(code,42903))
def deltaBelow1192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1193(code,U32.is_lt(code,42909))
def deltaBelow1195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1192(code,U32.is_lt(code,42906))
    case False{}: deltaBelow1194(code,U32.is_lt(code,42908))
def deltaBelow1196(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1191(code,U32.is_lt(code,42902))
    case False{}: deltaBelow1195(code,U32.is_lt(code,42907))
def deltaBelow1197(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1198(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1199(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1198(code,U32.is_lt(code,42914))
def deltaBelow1200(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1197(code,U32.is_lt(code,42911))
    case False{}: deltaBelow1199(code,U32.is_lt(code,42913))
def deltaBelow1201(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1202(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1201(code,U32.is_lt(code,42917))
def deltaBelow1203(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1204(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1203(code,U32.is_lt(code,42920))
def deltaBelow1205(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1202(code,U32.is_lt(code,42916))
    case False{}: deltaBelow1204(code,U32.is_lt(code,42919))
def deltaBelow1206(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1200(code,U32.is_lt(code,42912))
    case False{}: deltaBelow1205(code,U32.is_lt(code,42918))
def deltaBelow1207(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1196(code,U32.is_lt(code,42905))
    case False{}: deltaBelow1206(code,U32.is_lt(code,42915))
def deltaBelow1208(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1187(code,U32.is_lt(code,42884))
    case False{}: deltaBelow1207(code,U32.is_lt(code,42910))
def deltaBelow1209(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1168(code,U32.is_lt(code,42845))
    case False{}: deltaBelow1208(code,U32.is_lt(code,42898))
def deltaBelow1210(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294924988
def deltaBelow1211(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294924981
    case False{}: 4294924991
def deltaBelow1212(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294924977
    case False{}: deltaBelow1211(code,U32.is_lt(code,42925))
def deltaBelow1213(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1210(code,U32.is_lt(code,42922))
    case False{}: deltaBelow1212(code,U32.is_lt(code,42924))
def deltaBelow1214(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294924988
    case False{}: 0
def deltaBelow1215(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294925014
    case False{}: 4294925035
def deltaBelow1216(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294925038
    case False{}: deltaBelow1215(code,U32.is_lt(code,42930))
def deltaBelow1217(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1214(code,U32.is_lt(code,42927))
    case False{}: deltaBelow1216(code,U32.is_lt(code,42929))
def deltaBelow1218(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1213(code,U32.is_lt(code,42923))
    case False{}: deltaBelow1217(code,U32.is_lt(code,42928))
def deltaBelow1219(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 928
    case False{}: 1
def deltaBelow1220(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1221(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1220(code,U32.is_lt(code,42935))
def deltaBelow1222(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1219(code,U32.is_lt(code,42932))
    case False{}: deltaBelow1221(code,U32.is_lt(code,42934))
def deltaBelow1223(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1224(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1225(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1224(code,U32.is_lt(code,42940))
def deltaBelow1226(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1223(code,U32.is_lt(code,42937))
    case False{}: deltaBelow1225(code,U32.is_lt(code,42939))
def deltaBelow1227(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1222(code,U32.is_lt(code,42933))
    case False{}: deltaBelow1226(code,U32.is_lt(code,42938))
def deltaBelow1228(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1218(code,U32.is_lt(code,42926))
    case False{}: deltaBelow1227(code,U32.is_lt(code,42936))
def deltaBelow1229(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1230(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1231(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1230(code,U32.is_lt(code,42945))
def deltaBelow1232(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1229(code,U32.is_lt(code,42942))
    case False{}: deltaBelow1231(code,U32.is_lt(code,42944))
def deltaBelow1233(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1234(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294924989
    case False{}: 4294931912
def deltaBelow1235(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4294967248
    case False{}: deltaBelow1234(code,U32.is_lt(code,42950))
def deltaBelow1236(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1233(code,U32.is_lt(code,42947))
    case False{}: deltaBelow1235(code,U32.is_lt(code,42949))
def deltaBelow1237(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1232(code,U32.is_lt(code,42943))
    case False{}: deltaBelow1236(code,U32.is_lt(code,42948))
def deltaBelow1238(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1239(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294924953
def deltaBelow1240(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1239(code,U32.is_lt(code,42955))
def deltaBelow1241(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1238(code,U32.is_lt(code,42952))
    case False{}: deltaBelow1240(code,U32.is_lt(code,42954))
def deltaBelow1242(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1243(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1244(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1243(code,U32.is_lt(code,42960))
def deltaBelow1245(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1242(code,U32.is_lt(code,42957))
    case False{}: deltaBelow1244(code,U32.is_lt(code,42959))
def deltaBelow1246(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1241(code,U32.is_lt(code,42953))
    case False{}: deltaBelow1245(code,U32.is_lt(code,42958))
def deltaBelow1247(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1237(code,U32.is_lt(code,42946))
    case False{}: deltaBelow1246(code,U32.is_lt(code,42956))
def deltaBelow1248(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1228(code,U32.is_lt(code,42931))
    case False{}: deltaBelow1247(code,U32.is_lt(code,42951))
def deltaBelow1249(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1250(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1251(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1250(code,U32.is_lt(code,42965))
def deltaBelow1252(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1249(code,U32.is_lt(code,42962))
    case False{}: deltaBelow1251(code,U32.is_lt(code,42964))
def deltaBelow1253(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1254(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 1
def deltaBelow1255(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: deltaBelow1254(code,U32.is_lt(code,42970))
def deltaBelow1256(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1253(code,U32.is_lt(code,42967))
    case False{}: deltaBelow1255(code,U32.is_lt(code,42969))
def deltaBelow1257(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1252(code,U32.is_lt(code,42963))
    case False{}: deltaBelow1256(code,U32.is_lt(code,42968))
def deltaBelow1258(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4294924735
def deltaBelow1259(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 1
    case False{}: 0
def deltaBelow1260(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1259(code,U32.is_lt(code,42998))
def deltaBelow1261(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1258(code,U32.is_lt(code,42972))
    case False{}: deltaBelow1260(code,U32.is_lt(code,42997))
def deltaBelow1262(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def deltaBelow1263(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 40
def deltaBelow1264(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 40
    case False{}: deltaBelow1263(code,U32.is_lt(code,66736))
def deltaBelow1265(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1262(code,U32.is_lt(code,65339))
    case False{}: deltaBelow1264(code,U32.is_lt(code,66600))
def deltaBelow1266(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1261(code,U32.is_lt(code,42973))
    case False{}: deltaBelow1265(code,U32.is_lt(code,66560))
def deltaBelow1267(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1257(code,U32.is_lt(code,42966))
    case False{}: deltaBelow1266(code,U32.is_lt(code,65313))
def deltaBelow1268(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 39
def deltaBelow1269(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 39
    case False{}: 0
def deltaBelow1270(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1269(code,U32.is_lt(code,66955))
def deltaBelow1271(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1268(code,U32.is_lt(code,66928))
    case False{}: deltaBelow1270(code,U32.is_lt(code,66940))
def deltaBelow1272(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 39
    case False{}: 0
def deltaBelow1273(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 64
def deltaBelow1274(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 39
    case False{}: deltaBelow1273(code,U32.is_lt(code,68736))
def deltaBelow1275(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1272(code,U32.is_lt(code,66963))
    case False{}: deltaBelow1274(code,U32.is_lt(code,66966))
def deltaBelow1276(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1271(code,U32.is_lt(code,66939))
    case False{}: deltaBelow1275(code,U32.is_lt(code,66964))
def deltaBelow1277(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def deltaBelow1278(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def deltaBelow1279(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1278(code,U32.is_lt(code,71872))
def deltaBelow1280(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1277(code,U32.is_lt(code,68944))
    case False{}: deltaBelow1279(code,U32.is_lt(code,71840))
def deltaBelow1281(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 27
def deltaBelow1282(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: deltaBelow1281(code,U32.is_lt(code,93856))
def deltaBelow1283(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 34
    case False{}: 0
def deltaBelow1284(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: deltaBelow1283(code,U32.is_lt(code,125218))
def deltaBelow1285(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1282(code,U32.is_lt(code,93792))
    case False{}: deltaBelow1284(code,U32.is_lt(code,125184))
def deltaBelow1286(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1280(code,U32.is_lt(code,68966))
    case False{}: deltaBelow1285(code,U32.is_lt(code,93881))
def deltaBelow1287(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1276(code,U32.is_lt(code,66956))
    case False{}: deltaBelow1286(code,U32.is_lt(code,93760))
def deltaBelow1288(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1267(code,U32.is_lt(code,42971))
    case False{}: deltaBelow1287(code,U32.is_lt(code,68787))
def deltaBelow1289(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1248(code,U32.is_lt(code,42941))
    case False{}: deltaBelow1288(code,U32.is_lt(code,66772))
def deltaBelow1290(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1209(code,U32.is_lt(code,42874))
    case False{}: deltaBelow1289(code,U32.is_lt(code,42961))
def deltaBelow1291(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow1129(code,U32.is_lt(code,42590))
    case False{}: deltaBelow1290(code,U32.is_lt(code,42921))
def deltaBelow1292(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow968(code,U32.is_lt(code,7910))
    case False{}: deltaBelow1291(code,U32.is_lt(code,42825))
def deltaBelow1293(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: deltaBelow645(code,U32.is_lt(code,903))
    case False{}: deltaBelow1292(code,U32.is_lt(code,11447))

def delta(+code: U32) -> U32:
  deltaBelow1293(code,U32.is_lt(code,7740))
