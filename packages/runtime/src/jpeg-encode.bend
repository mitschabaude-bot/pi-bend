import Base
import ./image.bend as Image

# Baseline JFIF, three full-resolution components. Alpha is deliberately ignored.
# The fixed-point transform follows image-rs 0.24.8 / IJG; see tests/jpeg-encode.md
# and docs/licenses/jpeg-ijg.txt for source attribution and distribution terms.
type Error is Data:
  InvalidDimensions{}
  InvalidPixelCount{}
  InvalidQuality{}
  OutputLimit{}

type Row is Data:
  Row{a: U32,b: U32,c: U32,d: U32,e: U32,f: U32,g: U32,h: U32}
type Block is Data:
  Block{a: Row,b: Row,c: Row,d: Row,e: Row,f: Row,g: Row,h: Row}
type Color is Data:
  Color{y: U32,cb: U32,cr: U32}

def zigzag() -> List<&2,U32>:
  0 <> 1 <> 8 <> 16 <> 9 <> 2 <> 3 <> 10 <> 17 <> 24 <> 32 <> 25 <> 18 <> 11 <> 4 <> 5 <> 12 <> 19 <> 26 <> 33 <> 40 <> 48 <> 41 <> 34 <> 27 <> 20 <> 13 <> 6 <> 7 <> 14 <> 21 <> 28 <> 35 <> 42 <> 49 <> 56 <> 57 <> 50 <> 43 <> 36 <> 29 <> 22 <> 15 <> 23 <> 30 <> 37 <> 44 <> 51 <> 58 <> 59 <> 52 <> 45 <> 38 <> 31 <> 39 <> 46 <> 53 <> 60 <> 61 <> 54 <> 47 <> 55 <> 62 <> 63 <> Nil{}

def baseQuantum(index: U32) -> U32:
  match index:
    case 0: 16
    case 1: 11
    case 2: 10
    case 3: 16
    case 4: 24
    case 5: 40
    case 6: 51
    case 7: 61
    case 8: 12
    case 9: 12
    case 10: 14
    case 11: 19
    case 12: 26
    case 13: 58
    case 14: 60
    case 15: 55
    case 16: 14
    case 17: 13
    case 18: 16
    case 19: 24
    case 20: 40
    case 21: 57
    case 22: 69
    case 23: 56
    case 24: 14
    case 25: 17
    case 26: 22
    case 27: 29
    case 28: 51
    case 29: 87
    case 30: 80
    case 31: 62
    case 32: 18
    case 33: 22
    case 34: 37
    case 35: 56
    case 36: 68
    case 37: 109
    case 38: 103
    case 39: 77
    case 40: 24
    case 41: 35
    case 42: 55
    case 43: 64
    case 44: 81
    case 45: 104
    case 46: 113
    case 47: 92
    case 48: 49
    case 49: 64
    case 50: 78
    case 51: 87
    case 52: 103
    case 53: 121
    case 54: 120
    case 55: 101
    case 56: 72
    case 57: 92
    case 58: 95
    case 59: 98
    case 60: 112
    case 61: 100
    case 62: 103
    case 63: 99
    case 64: 17
    case 65: 18
    case 66: 24
    case 67: 47
    case 68: 99
    case 69: 99
    case 70: 99
    case 71: 99
    case 72: 18
    case 73: 21
    case 74: 26
    case 75: 66
    case 76: 99
    case 77: 99
    case 78: 99
    case 79: 99
    case 80: 24
    case 81: 26
    case 82: 56
    case 83: 99
    case 84: 99
    case 85: 99
    case 86: 99
    case 87: 99
    case 88: 47
    case 89: 66
    case 90: 99
    case 91: 99
    case 92: 99
    case 93: 99
    case 94: 99
    case 95: 99
    case 96: 99
    case 97: 99
    case 98: 99
    case 99: 99
    case 100: 99
    case 101: 99
    case 102: 99
    case 103: 99
    case 104: 99
    case 105: 99
    case 106: 99
    case 107: 99
    case 108: 99
    case 109: 99
    case 110: 99
    case 111: 99
    case 112: 99
    case 113: 99
    case 114: 99
    case 115: 99
    case 116: 99
    case 117: 99
    case 118: 99
    case 119: 99
    case 120: 99
    case 121: 99
    case 122: 99
    case 123: 99
    case 124: 99
    case 125: 99
    case 126: 99
    case 127: 99
    case _: 1

def huffmanHeader0() -> List<&2,U32>:
  0 <> 0 <> 1 <> 5 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 2 <> 3 <> 4 <> 5 <> 6 <> 7 <> 8 <> 9 <> 10 <> 11 <> Nil{}

def huffmanHeader1() -> List<&2,U32>:
  16 <> 0 <> 2 <> 1 <> 3 <> 3 <> 2 <> 4 <> 3 <> 5 <> 5 <> 4 <> 4 <> 0 <> 0 <> 1 <> 125 <> 1 <> 2 <> 3 <> 0 <> 4 <> 17 <> 5 <> 18 <> 33 <> 49 <> 65 <> 6 <> 19 <> 81 <> 97 <> 7 <> 34 <> 113 <> 20 <> 50 <> 129 <> 145 <> 161 <> 8 <> 35 <> 66 <> 177 <> 193 <> 21 <> 82 <> 209 <> 240 <> 36 <> 51 <> 98 <> 114 <> 130 <> 9 <> 10 <> 22 <> 23 <> 24 <> 25 <> 26 <> 37 <> 38 <> 39 <> 40 <> 41 <> 42 <> 52 <> 53 <> 54 <> 55 <> 56 <> 57 <> 58 <> 67 <> 68 <> 69 <> 70 <> 71 <> 72 <> 73 <> 74 <> 83 <> 84 <> 85 <> 86 <> 87 <> 88 <> 89 <> 90 <> 99 <> 100 <> 101 <> 102 <> 103 <> 104 <> 105 <> 106 <> 115 <> 116 <> 117 <> 118 <> 119 <> 120 <> 121 <> 122 <> 131 <> 132 <> 133 <> 134 <> 135 <> 136 <> 137 <> 138 <> 146 <> 147 <> 148 <> 149 <> 150 <> 151 <> 152 <> 153 <> 154 <> 162 <> 163 <> 164 <> 165 <> 166 <> 167 <> 168 <> 169 <> 170 <> 178 <> 179 <> 180 <> 181 <> 182 <> 183 <> 184 <> 185 <> 186 <> 194 <> 195 <> 196 <> 197 <> 198 <> 199 <> 200 <> 201 <> 202 <> 210 <> 211 <> 212 <> 213 <> 214 <> 215 <> 216 <> 217 <> 218 <> 225 <> 226 <> 227 <> 228 <> 229 <> 230 <> 231 <> 232 <> 233 <> 234 <> 241 <> 242 <> 243 <> 244 <> 245 <> 246 <> 247 <> 248 <> 249 <> 250 <> Nil{}

def huffmanHeader2() -> List<&2,U32>:
  1 <> 0 <> 3 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 2 <> 3 <> 4 <> 5 <> 6 <> 7 <> 8 <> 9 <> 10 <> 11 <> Nil{}

def huffmanHeader3() -> List<&2,U32>:
  17 <> 0 <> 2 <> 1 <> 2 <> 4 <> 4 <> 3 <> 4 <> 7 <> 5 <> 4 <> 4 <> 0 <> 1 <> 2 <> 119 <> 0 <> 1 <> 2 <> 3 <> 17 <> 4 <> 5 <> 33 <> 49 <> 6 <> 18 <> 65 <> 81 <> 7 <> 97 <> 113 <> 19 <> 34 <> 50 <> 129 <> 8 <> 20 <> 66 <> 145 <> 161 <> 177 <> 193 <> 9 <> 35 <> 51 <> 82 <> 240 <> 21 <> 98 <> 114 <> 209 <> 10 <> 22 <> 36 <> 52 <> 225 <> 37 <> 241 <> 23 <> 24 <> 25 <> 26 <> 38 <> 39 <> 40 <> 41 <> 42 <> 53 <> 54 <> 55 <> 56 <> 57 <> 58 <> 67 <> 68 <> 69 <> 70 <> 71 <> 72 <> 73 <> 74 <> 83 <> 84 <> 85 <> 86 <> 87 <> 88 <> 89 <> 90 <> 99 <> 100 <> 101 <> 102 <> 103 <> 104 <> 105 <> 106 <> 115 <> 116 <> 117 <> 118 <> 119 <> 120 <> 121 <> 122 <> 130 <> 131 <> 132 <> 133 <> 134 <> 135 <> 136 <> 137 <> 138 <> 146 <> 147 <> 148 <> 149 <> 150 <> 151 <> 152 <> 153 <> 154 <> 162 <> 163 <> 164 <> 165 <> 166 <> 167 <> 168 <> 169 <> 170 <> 178 <> 179 <> 180 <> 181 <> 182 <> 183 <> 184 <> 185 <> 186 <> 194 <> 195 <> 196 <> 197 <> 198 <> 199 <> 200 <> 201 <> 202 <> 210 <> 211 <> 212 <> 213 <> 214 <> 215 <> 216 <> 217 <> 218 <> 226 <> 227 <> 228 <> 229 <> 230 <> 231 <> 232 <> 233 <> 234 <> 242 <> 243 <> 244 <> 245 <> 246 <> 247 <> 248 <> 249 <> 250 <> Nil{}

# Packed code length and canonical code; keys identify the four standard tables.
def huffman(key: U32) -> U32:
  match key:
    case 0: 131072
    case 1: 196610
    case 2: 196611
    case 3: 196612
    case 4: 196613
    case 5: 196614
    case 6: 262158
    case 7: 327710
    case 8: 393278
    case 9: 458878
    case 10: 524542
    case 11: 590334
    case 257: 131072
    case 258: 131073
    case 259: 196612
    case 256: 262154
    case 260: 262155
    case 273: 262156
    case 261: 327706
    case 274: 327707
    case 289: 327708
    case 305: 393274
    case 321: 393275
    case 262: 458872
    case 275: 458873
    case 337: 458874
    case 353: 458875
    case 263: 524536
    case 290: 524537
    case 369: 524538
    case 276: 590326
    case 306: 590327
    case 385: 590328
    case 401: 590329
    case 417: 590330
    case 264: 656374
    case 291: 656375
    case 322: 656376
    case 433: 656377
    case 449: 656378
    case 277: 722934
    case 338: 722935
    case 465: 722936
    case 496: 722937
    case 292: 790516
    case 307: 790517
    case 354: 790518
    case 370: 790519
    case 386: 1015744
    case 265: 1113986
    case 266: 1113987
    case 278: 1113988
    case 279: 1113989
    case 280: 1113990
    case 281: 1113991
    case 282: 1113992
    case 293: 1113993
    case 294: 1113994
    case 295: 1113995
    case 296: 1113996
    case 297: 1113997
    case 298: 1113998
    case 308: 1113999
    case 309: 1114000
    case 310: 1114001
    case 311: 1114002
    case 312: 1114003
    case 313: 1114004
    case 314: 1114005
    case 323: 1114006
    case 324: 1114007
    case 325: 1114008
    case 326: 1114009
    case 327: 1114010
    case 328: 1114011
    case 329: 1114012
    case 330: 1114013
    case 339: 1114014
    case 340: 1114015
    case 341: 1114016
    case 342: 1114017
    case 343: 1114018
    case 344: 1114019
    case 345: 1114020
    case 346: 1114021
    case 355: 1114022
    case 356: 1114023
    case 357: 1114024
    case 358: 1114025
    case 359: 1114026
    case 360: 1114027
    case 361: 1114028
    case 362: 1114029
    case 371: 1114030
    case 372: 1114031
    case 373: 1114032
    case 374: 1114033
    case 375: 1114034
    case 376: 1114035
    case 377: 1114036
    case 378: 1114037
    case 387: 1114038
    case 388: 1114039
    case 389: 1114040
    case 390: 1114041
    case 391: 1114042
    case 392: 1114043
    case 393: 1114044
    case 394: 1114045
    case 402: 1114046
    case 403: 1114047
    case 404: 1114048
    case 405: 1114049
    case 406: 1114050
    case 407: 1114051
    case 408: 1114052
    case 409: 1114053
    case 410: 1114054
    case 418: 1114055
    case 419: 1114056
    case 420: 1114057
    case 421: 1114058
    case 422: 1114059
    case 423: 1114060
    case 424: 1114061
    case 425: 1114062
    case 426: 1114063
    case 434: 1114064
    case 435: 1114065
    case 436: 1114066
    case 437: 1114067
    case 438: 1114068
    case 439: 1114069
    case 440: 1114070
    case 441: 1114071
    case 442: 1114072
    case 450: 1114073
    case 451: 1114074
    case 452: 1114075
    case 453: 1114076
    case 454: 1114077
    case 455: 1114078
    case 456: 1114079
    case 457: 1114080
    case 458: 1114081
    case 466: 1114082
    case 467: 1114083
    case 468: 1114084
    case 469: 1114085
    case 470: 1114086
    case 471: 1114087
    case 472: 1114088
    case 473: 1114089
    case 474: 1114090
    case 481: 1114091
    case 482: 1114092
    case 483: 1114093
    case 484: 1114094
    case 485: 1114095
    case 486: 1114096
    case 487: 1114097
    case 488: 1114098
    case 489: 1114099
    case 490: 1114100
    case 497: 1114101
    case 498: 1114102
    case 499: 1114103
    case 500: 1114104
    case 501: 1114105
    case 502: 1114106
    case 503: 1114107
    case 504: 1114108
    case 505: 1114109
    case 506: 1114110
    case 512: 131072
    case 513: 131073
    case 514: 131074
    case 515: 196614
    case 516: 262158
    case 517: 327710
    case 518: 393278
    case 519: 458878
    case 520: 524542
    case 521: 590334
    case 522: 656382
    case 523: 722942
    case 768: 131072
    case 769: 131073
    case 770: 196612
    case 771: 262154
    case 785: 262155
    case 772: 327704
    case 773: 327705
    case 801: 327706
    case 817: 327707
    case 774: 393272
    case 786: 393273
    case 833: 393274
    case 849: 393275
    case 775: 458872
    case 865: 458873
    case 881: 458874
    case 787: 524534
    case 802: 524535
    case 818: 524536
    case 897: 524537
    case 776: 590324
    case 788: 590325
    case 834: 590326
    case 913: 590327
    case 929: 590328
    case 945: 590329
    case 961: 590330
    case 777: 656374
    case 803: 656375
    case 819: 656376
    case 850: 656377
    case 1008: 656378
    case 789: 722934
    case 866: 722935
    case 882: 722936
    case 977: 722937
    case 778: 790516
    case 790: 790517
    case 804: 790518
    case 820: 790519
    case 993: 933856
    case 805: 1015746
    case 1009: 1015747
    case 791: 1113992
    case 792: 1113993
    case 793: 1113994
    case 794: 1113995
    case 806: 1113996
    case 807: 1113997
    case 808: 1113998
    case 809: 1113999
    case 810: 1114000
    case 821: 1114001
    case 822: 1114002
    case 823: 1114003
    case 824: 1114004
    case 825: 1114005
    case 826: 1114006
    case 835: 1114007
    case 836: 1114008
    case 837: 1114009
    case 838: 1114010
    case 839: 1114011
    case 840: 1114012
    case 841: 1114013
    case 842: 1114014
    case 851: 1114015
    case 852: 1114016
    case 853: 1114017
    case 854: 1114018
    case 855: 1114019
    case 856: 1114020
    case 857: 1114021
    case 858: 1114022
    case 867: 1114023
    case 868: 1114024
    case 869: 1114025
    case 870: 1114026
    case 871: 1114027
    case 872: 1114028
    case 873: 1114029
    case 874: 1114030
    case 883: 1114031
    case 884: 1114032
    case 885: 1114033
    case 886: 1114034
    case 887: 1114035
    case 888: 1114036
    case 889: 1114037
    case 890: 1114038
    case 898: 1114039
    case 899: 1114040
    case 900: 1114041
    case 901: 1114042
    case 902: 1114043
    case 903: 1114044
    case 904: 1114045
    case 905: 1114046
    case 906: 1114047
    case 914: 1114048
    case 915: 1114049
    case 916: 1114050
    case 917: 1114051
    case 918: 1114052
    case 919: 1114053
    case 920: 1114054
    case 921: 1114055
    case 922: 1114056
    case 930: 1114057
    case 931: 1114058
    case 932: 1114059
    case 933: 1114060
    case 934: 1114061
    case 935: 1114062
    case 936: 1114063
    case 937: 1114064
    case 938: 1114065
    case 946: 1114066
    case 947: 1114067
    case 948: 1114068
    case 949: 1114069
    case 950: 1114070
    case 951: 1114071
    case 952: 1114072
    case 953: 1114073
    case 954: 1114074
    case 962: 1114075
    case 963: 1114076
    case 964: 1114077
    case 965: 1114078
    case 966: 1114079
    case 967: 1114080
    case 968: 1114081
    case 969: 1114082
    case 970: 1114083
    case 978: 1114084
    case 979: 1114085
    case 980: 1114086
    case 981: 1114087
    case 982: 1114088
    case 983: 1114089
    case 984: 1114090
    case 985: 1114091
    case 986: 1114092
    case 994: 1114093
    case 995: 1114094
    case 996: 1114095
    case 997: 1114096
    case 998: 1114097
    case 999: 1114098
    case 1000: 1114099
    case 1001: 1114100
    case 1002: 1114101
    case 1010: 1114102
    case 1011: 1114103
    case 1012: 1114104
    case 1013: 1114105
    case 1014: 1114106
    case 1015: 1114107
    case 1016: 1114108
    case 1017: 1114109
    case 1018: 1114110
    case _: 0

# Signed coefficients use bounded two's-complement U32 arithmetic. Both FDCT
# passes stay within signed 32-bit range; this shift restores the sign bits.
def shift(+value: U32, +bits: Nat) -> U32:
  U32.or(U32.shrn(value,bits),Bool.pick(U32,U32.is_ge(value,2147483648),U32.shln(4294967295,Nat.sub(32n,bits)),0))

def magnitude(+value: U32) -> U32:
  Bool.pick(U32,U32.is_ge(value,2147483648),(0 - value : U32),value)

def transformRow(+first: Bool, row: Row) -> Row:
  match row:
    case Row{+a,+b,+c,+d,+e,+f,+g,+h}:
      +s0 = (a + h : U32)
      +s1 = (b + g : U32)
      +s2 = (c + f : U32)
      +s3 = (d + e : U32)
      +u0 = (a - h : U32)
      +u1 = (b - g : U32)
      +u2 = (c - f : U32)
      +u3 = (d - e : U32)
      +v0 = (s0 + s3 : U32)
      +v1 = (s1 + s2 : U32)
      +v2 = (s0 - s3 : U32)
      +v3 = (s1 - s2 : U32)
      +even = ((v2 + v3) * 4433 + Bool.pick(U32,first,1024,16384) : U32)
      +odd = ((u0 + u2 + u1 + u3) * 9633 + 1024 : U32)
      +p = (odd - (u0 + u2) * 3196 : U32)
      +q = (odd - (u1 + u3) * 16069 : U32)
      +r = ((0 - u0 - u3) * 7373 : U32)
      +s = ((0 - u1 - u2) * 20995 : U32)
      +bits = Bool.pick(Nat,first,11n,15n)
      Row{
        Bool.pick(U32,first,U32.shln((v0 + v1 - 1024 : U32),2n),shift((v0 + v1 + 2 : U32),2n)),
        shift((u0 * 12299 + r + p : U32),bits),
        shift((even + v2 * 6270 : U32),bits),
        shift((u1 * 25172 + s + q : U32),bits),
        Bool.pick(U32,first,U32.shln((v0 - v1 : U32),2n),shift((v0 - v1 + 2 : U32),2n)),
        shift((u2 * 16819 + s + p : U32),bits),
        shift((even - v3 * 15137 : U32),bits),
        shift((u3 * 2446 + r + q : U32),bits)}

def transformRows(+first: Bool, block: Block) -> Block:
  match block:
    case Block{a,b,c,d,e,f,g,h}: Block{transformRow(first,a),transformRow(first,b),transformRow(first,c),transformRow(first,d),transformRow(first,e),transformRow(first,f),transformRow(first,g),transformRow(first,h)}

def transpose(block: Block) -> Block:
  match block:
    case Block{Row{a0,a1,a2,a3,a4,a5,a6,a7},Row{b0,b1,b2,b3,b4,b5,b6,b7},Row{c0,c1,c2,c3,c4,c5,c6,c7},Row{d0,d1,d2,d3,d4,d5,d6,d7},Row{e0,e1,e2,e3,e4,e5,e6,e7},Row{f0,f1,f2,f3,f4,f5,f6,f7},Row{g0,g1,g2,g3,g4,g5,g6,g7},Row{h0,h1,h2,h3,h4,h5,h6,h7}}:
      Block{Row{a0,b0,c0,d0,e0,f0,g0,h0},Row{a1,b1,c1,d1,e1,f1,g1,h1},Row{a2,b2,c2,d2,e2,f2,g2,h2},Row{a3,b3,c3,d3,e3,f3,g3,h3},Row{a4,b4,c4,d4,e4,f4,g4,h4},Row{a5,b5,c5,d5,e5,f5,g5,h5},Row{a6,b6,c6,d6,e6,f6,g6,h6},Row{a7,b7,c7,d7,e7,f7,g7,h7}}

def transform(block: Block) -> Block:
  transpose(transformRows(False{},transpose(transformRows(True{},block))))

def rowValue(row: Row, index: U32) -> U32:
  match row index:
    case Row{a,_,_,_,_,_,_,_} 0: a
    case Row{_,b,_,_,_,_,_,_} 1: b
    case Row{_,_,c,_,_,_,_,_} 2: c
    case Row{_,_,_,d,_,_,_,_} 3: d
    case Row{_,_,_,_,e,_,_,_} 4: e
    case Row{_,_,_,_,_,f,_,_} 5: f
    case Row{_,_,_,_,_,_,g,_} 6: g
    case Row{_,_,_,_,_,_,_,h} _: h

def blockRow(block: Block, index: U32) -> Row:
  match block index:
    case Block{a,_,_,_,_,_,_,_} 0: a
    case Block{_,b,_,_,_,_,_,_} 1: b
    case Block{_,_,c,_,_,_,_,_} 2: c
    case Block{_,_,_,d,_,_,_,_} 3: d
    case Block{_,_,_,_,e,_,_,_} 4: e
    case Block{_,_,_,_,_,f,_,_} 5: f
    case Block{_,_,_,_,_,_,g,_} 6: g
    case Block{_,_,_,_,_,_,_,h} _: h

def blockValue(block: Block, +index: U32) -> U32:
  rowValue(blockRow(block,(index / 8 : U32)),(index % 8 : U32))

def color(+pixel: U32) -> Color:
  +r = U32.to_f32(U32.shrn(pixel,24n))
  +g = U32.to_f32(U32.and(U32.shrn(pixel,16n),255))
  +b = U32.to_f32(U32.and(U32.shrn(pixel,8n),255))
  Color{
    F32.to_u32(F32.clamp((76.245 / 255.0 * r + 149.685 / 255.0 * g + 29.07 / 255.0 * b : F32),0.0,255.0)),
    F32.to_u32(F32.clamp((0.0 - 43.0185 / 255.0 * r - 84.4815 / 255.0 * g + 127.5 / 255.0 * b + 128.0 : F32),0.0,255.0)),
    F32.to_u32(F32.clamp((127.5 / 255.0 * r - 106.7685 / 255.0 * g - 20.7315 / 255.0 * b + 128.0 : F32),0.0,255.0))}

def component(pixelColor: Color, plane: U32) -> U32:
  match pixelColor plane:
    case Color{y,_,_} 0: y
    case Color{_,cb,_} 1: cb
    case Color{_,_,cr} _: cr

def sampleRows(colors: List<&2,Color>, +plane: U32) -> List<&2,Row>:
  match colors:
    case a <> b <> c <> d <> e <> f <> g <> h <> rest:
      Row{component(a,plane),component(b,plane),component(c,plane),component(d,plane),component(e,plane),component(f,plane),component(g,plane),component(h,plane)} <> sampleRows(rest,plane)
    case _: Nil{}

def zeroRow() -> Row: Row{0,0,0,0,0,0,0,0}

def sampleBlock(rows: List<&2,Row>) -> Block:
  match rows:
    case a <> b <> c <> d <> e <> f <> g <> h <> Nil{}: Block{a,b,c,d,e,f,g,h}
    case _: Block{zeroRow(),zeroRow(),zeroRow(),zeroRow(),zeroRow(),zeroRow(),zeroRow(),zeroRow()}

def scale(+quality: U32) -> U32:
  +bounded = U32.min(100,U32.max(1,quality))
  Bool.pick(Unit -> U32,U32.is_lt(bounded,50),_ => (5000 / bounded : U32),_ => (200 - bounded * 2 : U32))(Unit{})

def quantum(qualityScale: U32, chroma: Bool, index: U32) -> U32:
  U32.max(1,U32.min(255,((baseQuantum((Bool.pick(U32,chroma,64,0) + index : U32)) * qualityScale + 50) / 100 : U32)))

# Truncate the FDCT's factor of eight before quantization, then round ties away
# from zero. Integer arithmetic is exact for this bounded rational operation.
def coefficient(+value: U32, +step: U32) -> U32:
  +rounded = ((magnitude(value) / 8 * 2 + step) / (step * 2) : U32)
  Bool.pick(U32,U32.is_ge(value,2147483648),(0 - rounded : U32),rounded)

type Bytes is Data:
  Bytes{reversed: List<&2,U32>, remaining: Nat, overflow: Bool}
type Writer is Data:
  Writer{bytes: Bytes, bits: U32, count: U32}

def byte(value: U32, bytes: Bytes) -> Bytes:
  match bytes:
    case Bytes{reversed,0n,_}: Bytes{reversed,0n,True{}}
    case Bytes{reversed,1n+n,overflow}: Bytes{value <> reversed,n,overflow}

def raw(values: List<&2,U32>, bytes: Bytes) -> Bytes:
  match values:
    case Nil{}: bytes
    case value <> rest: raw(rest,byte(value,bytes))

def stuffed(+value: U32, bytes: Bytes) -> Bytes:
  +written = byte(value,bytes)
  Bool.pick(Unit -> Bytes,U32.is_eq(value,255),_ => byte(0,written),_ => written)(Unit{})

def flush(fuel: Nat, writer: Writer) -> Writer:
  match fuel writer:
    case 0n state: state
    case 1n+n Writer{+bytes,+bits,+count}:
      Bool.pick(Unit -> Writer,U32.is_ge(count,8),
        _ => flush(n,Writer{stuffed(U32.and(U32.shrn(bits,U32.to_nat((count - 8 : U32))),255),bytes),bits,(count - 8 : U32)}),
        _ => Writer{bytes,bits,count})(Unit{})

def writeBits(value: U32, +size: U32, writer: Writer) -> Writer:
  match writer:
    case Writer{bytes,bits,count}: flush(3n,Writer{bytes,U32.or(U32.shln(bits,U32.to_nat(size)),value),(count + size : U32)})

def symbol(table: U32, value: U32, writer: Writer) -> Writer:
  +code = huffman((table * 256 + value : U32))
  writeBits(U32.and(code,65535),U32.shrn(code,16n),writer)

def bitLength(fuel: Nat, +value: U32, +size: U32) -> U32:
  match fuel:
    case 0n: size
    case 1n+n: Bool.pick(Unit -> U32,U32.is_eq(value,0),_ => size,_ => bitLength(n,U32.shr(value),(size + 1 : U32)))(Unit{})

def valueBits(+value: U32, size: U32) -> U32:
  U32.and(Bool.pick(U32,U32.is_ge(value,2147483648),(value - 1 : U32),value),(U32.shln(1,U32.to_nat(size)) - 1 : U32))

def zeroRuns(count: Nat, +table: U32, writer: Writer) -> Writer:
  match count:
    case 0n: writer
    case 1n+n: zeroRuns(n,table,symbol(table,240,writer))

type AcState is Data:
  AcState{zeros: U32, writer: Writer}

def acCoefficient(zero: Bool, +value: U32, +table: U32, state: AcState) -> AcState:
  match zero state:
    case True{} AcState{zeros,writer}: AcState{(zeros + 1 : U32),writer}
    case False{} AcState{+zeros,writer}:
      +size = bitLength(16n,magnitude(value),0)
      encoded = symbol(table,((zeros % 16) * 16 + size : U32),zeroRuns(U32.to_nat((zeros / 16 : U32)),table,writer))
      AcState{0,writeBits(valueBits(value,size),size,encoded)}

def ac(indices: List<&2,U32>, +block: Block, +qualityScale: U32, +chroma: Bool, +table: U32, state: AcState) -> AcState:
  match indices:
    case Nil{}: state
    case +index <> rest:
      +value = coefficient(blockValue(block,index),quantum(qualityScale,chroma,index))
      ac(rest,block,qualityScale,chroma,table,acCoefficient(U32.is_eq(value,0),value,table,state))

def endBlock(table: U32, state: AcState) -> Writer:
  match state:
    case AcState{0,writer}: writer
    case AcState{_,writer}: symbol(table,0,writer)

def acIndices(indices: List<&2,U32>) -> List<&2,U32>:
  match indices:
    case _ <> rest: rest
    case Nil{}: Nil{}

type Channel is Data:
  Channel{dc: U32, writer: Writer}

def writeBlock(+block: Block, +qualityScale: U32, +chroma: Bool, previous: U32, writer: Writer) -> Channel:
  +dc = coefficient(blockValue(block,0),quantum(qualityScale,chroma,0))
  +difference = (dc - previous : U32)
  +size = bitLength(16n,magnitude(difference),0)
  +table = Bool.pick(U32,chroma,2,0)
  start = writeBits(valueBits(difference,size),size,symbol(table,size,writer))
  Channel{dc,endBlock((table + 1 : U32),ac(acIndices(zigzag()),block,qualityScale,chroma,(table + 1 : U32),AcState{0,start}))}

def quantization(indices: List<&2,U32>, +qualityScale: U32, +chroma: Bool) -> List<&2,U32>:
  match indices:
    case Nil{}: Nil{}
    case index <> rest: quantum(qualityScale,chroma,index) <> quantization(rest,qualityScale,chroma)

def segment(marker: U32, +body: List<&2,U32>, bytes: Bytes) -> Bytes:
  +length = (U32.from_nat(List.length(&2,U32,body)) + 2 : U32)
  raw(body,raw(255 <> marker <> U32.shrn(length,8n) <> U32.and(length,255) <> Nil{},bytes))

def headers(+width: U32, +height: U32, +qualityScale: U32, limit: Nat) -> Writer:
  start = raw(255 <> 216 <> Nil{},Bytes{Nil{},limit,False{}})
  jfif = segment(224,74 <> 70 <> 73 <> 70 <> 0 <> 1 <> 2 <> 0 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> Nil{},start)
  frame = segment(192,8 <> U32.shrn(height,8n) <> U32.and(height,255) <> U32.shrn(width,8n) <> U32.and(width,255) <> 3 <> 1 <> 17 <> 0 <> 2 <> 17 <> 1 <> 3 <> 17 <> 1 <> Nil{},jfif)
  luma = segment(219,0 <> quantization(zigzag(),qualityScale,False{}),frame)
  chroma = segment(219,1 <> quantization(zigzag(),qualityScale,True{}),luma)
  dcY = segment(196,huffmanHeader0(),chroma)
  acY = segment(196,huffmanHeader1(),dcY)
  dcC = segment(196,huffmanHeader2(),acY)
  acC = segment(196,huffmanHeader3(),dcC)
  Writer{segment(218,3 <> 1 <> 0 <> 2 <> 17 <> 3 <> 17 <> 0 <> 63 <> 0 <> Nil{},acC),0,0}

def full(writer: Writer) -> Bool:
  match writer:
    case Writer{Bytes{_,_,overflow},_,_}: overflow

def completed(bytes: Bytes) -> Result<&2,&2,Error,List<&2,U32>>:
  match bytes:
    case Bytes{_,_,True{}}: Fail{OutputLimit{}}
    case Bytes{reversed,_,False{}}: Done{List.reverse(&2,U32,reversed)}

def finishWriter(writer: Writer) -> Result<&2,&2,Error,List<&2,U32>>:
  match writer:
    case Writer{bytes,_,_}: completed(raw(255 <> 217 <> Nil{},bytes))

type Samples is Type:
  Samples{pixels: Array<U32>, reversed: List<&2,Color>}

def sampled(previous: List<&2,Color>, fetched: Array<U32> & U32) -> Samples:
  match fetched:
    case (pixels,value): Samples{pixels,color(value) <> previous}

def gather(fuel: Nat, +index: U32, +x: U32, +y: U32, +width: U32, +height: U32, state: Samples) -> Samples:
  match fuel state:
    case 0n result: result
    case 1n+n Samples{pixels,reversed}:
      position = (U32.min((height - 1 : U32),(y + index / 8 : U32)) * width + U32.min((width - 1 : U32),(x + index % 8 : U32)) : U32)
      gather(n,(index + 1 : U32),x,y,width,height,sampled(reversed,Array.get(U32,pixels,position)))

type Channels is Data:
  Channels{writer: Writer, y: U32, cb: U32, cr: U32}

def planeWritten(plane: U32, y: U32, cb: U32, cr: U32, result: Channel) -> Channels:
  match plane result:
    case 0 Channel{dc,writer}: Channels{writer,dc,cb,cr}
    case 1 Channel{dc,writer}: Channels{writer,y,dc,cr}
    case _ Channel{dc,writer}: Channels{writer,y,cb,dc}

def writePlane(+plane: U32, colors: List<&2,Color>, qualityScale: U32, state: Channels) -> Channels:
  match state:
    case Channels{writer,+y,+cb,+cr}:
      previous = Bool.pick(U32,U32.is_eq(plane,0),y,Bool.pick(U32,U32.is_eq(plane,1),cb,cr))
      planeWritten(plane,y,cb,cr,writeBlock(transform(sampleBlock(sampleRows(colors,plane))),qualityScale,U32.is_ne(plane,0),previous,writer))

type Encoding is Type:
  Encoding{pixels: Array<U32>, channels: Channels}

def encodeSamples(+qualityScale: U32, state: Channels, samples: Samples) -> Encoding:
  match samples:
    case Samples{pixels,reversed}:
      +colors = List.reverse(&2,Color,reversed)
      Encoding{pixels,writePlane(2,colors,qualityScale,writePlane(1,colors,qualityScale,writePlane(0,colors,qualityScale,state)))}

def encodeBlock(x: U32, y: U32, width: U32, height: U32, qualityScale: U32, state: Encoding) -> Encoding:
  match state:
    case Encoding{pixels,channels}: encodeSamples(qualityScale,channels,gather(64n,0,x,y,width,height,Samples{pixels,Nil{}}))

def encodeBlocks(fuel: Nat, +index: U32, +columns: U32, +width: U32, +height: U32, +qualityScale: U32, state: Encoding) -> Encoding:
  match fuel state:
    case 0n result: result
    case 1n+n Encoding{pixels,Channels{+writer,dcY,dcCb,dcCr}}:
      Bool.pick(Encoding -> Encoding,full(writer),value => value,
        value => encodeBlocks(n,(index + 1 : U32),columns,width,height,qualityScale,encodeBlock((index % columns * 8 : U32),(index / columns * 8 : U32),width,height,qualityScale,value)))(Encoding{pixels,Channels{writer,dcY,dcCb,dcCr}})

def encoded(width: U32, height: U32, state: Encoding) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  match state:
    case Encoding{pixels,Channels{writer,_,_,_}}: (Image.Raster{width,height,pixels},finishWriter(writeBits(127,7,writer)))

def encodeValid(quality: U32, limit: Nat, image: Image.Raster) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  match image:
    case Image.Raster{+width,+height,pixels}:
      +columns = ((width + 7) / 8 : U32)
      +qualityScale = scale(quality)
      encoded(width,height,encodeBlocks(U32.to_nat((columns * ((height + 7) / 8) : U32)),0,columns,width,height,qualityScale,Encoding{pixels,Channels{headers(width,height,qualityScale,limit),0,0,0}}))

def capacity(quality: U32, limit: Nat, +width: U32, +height: U32, sized: Array<U32> & U32) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  match sized:
    case (pixels,count):
      Bool.pick(Image.Raster -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>,U32.is_ge(count,(width * height : U32)),
        value => encodeValid(quality,limit,value),value => (value,Fail{InvalidPixelCount{}}))(Image.Raster{width,height,pixels})

def dimensions(quality: U32, limit: Nat, image: Image.Raster) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  match image:
    case Image.Raster{+width,+height,pixels}:
      Bool.pick(Array<U32> -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>,Image.validDimensions(width,height) && U32.is_le(width,65535) && U32.is_le(height,65535),
        value => capacity(quality,limit,width,height,Array.size(U32,value)),
        value => (Image.Raster{width,height,value},Fail{InvalidDimensions{}}))(pixels)

# The source API accepts u8 quality and clamps it to 1..100. Values outside u8
# are rejected, rather than emulating the WASM/JS binding's numeric truncation.
# The byte limit includes markers, tables, entropy stuffing and the final EOI.
def encode(image: Image.Raster, +quality: U32, limit: Nat) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  Bool.pick(Image.Raster -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>,U32.is_le(quality,255),
    value => dimensions(quality,limit,value),value => (value,Fail{InvalidQuality{}}))(image)
