// file = 0; split type = patterns; threshold = 100000; total count = 0.
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include "rmapats.h"

void  schedNewEvent (struct dummyq_struct * I1443, EBLK  * I1438, U  I628);
void  schedNewEvent (struct dummyq_struct * I1443, EBLK  * I1438, U  I628)
{
    U  I1727;
    U  I1728;
    U  I1729;
    struct futq * I1730;
    struct dummyq_struct * pQ = I1443;
    I1727 = ((U )vcs_clocks) + I628;
    I1729 = I1727 & ((1 << fHashTableSize) - 1);
    I1438->I674 = (EBLK  *)(-1);
    I1438->I675 = I1727;
    if (0 && rmaProfEvtProp) {
        vcs_simpSetEBlkEvtID(I1438);
    }
    if (I1727 < (U )vcs_clocks) {
        I1728 = ((U  *)&vcs_clocks)[1];
        sched_millenium(pQ, I1438, I1728 + 1, I1727);
    }
    else if ((peblkFutQ1Head != ((void *)0)) && (I628 == 1)) {
        I1438->I677 = (struct eblk *)peblkFutQ1Tail;
        peblkFutQ1Tail->I674 = I1438;
        peblkFutQ1Tail = I1438;
    }
    else if ((I1730 = pQ->I1344[I1729].I697)) {
        I1438->I677 = (struct eblk *)I1730->I695;
        I1730->I695->I674 = (RP )I1438;
        I1730->I695 = (RmaEblk  *)I1438;
    }
    else {
        sched_hsopt(pQ, I1438, I1727);
    }
}
void  rmaPropagate13_p_simv_daidir (UB  * pcode, scalar  val)
{
    if (*(pcode + 2) == val) {
        if (fRTFrcRelCbk) {
            U  I1535 = 0;
            if (fScalarIsForced) {
                I1535 = 29;
            }
            else if (fScalarIsReleased) {
                I1535 = 30;
            }
            if ((fScalarIsForced || fScalarIsReleased) && fRTFrcRelCbk) {
                RP  I1583 = ((void *)0);
                I1583 = (RP )(pcode + 8);
                if (I1583) {
                    void * I1584 = hsimGetCbkMemOptCallback(I1583);
                    if (I1584) {
                        SDaicbForHsimNoFlagFrcRel(I1584, I1535, -1, -1, -1);
                    }
                }
                fScalarIsForced = 0;
                fScalarIsReleased = 0;
            }
        }
        return  ;
    }
    *(pcode + 2) = val;
    if (fRTFrcRelCbk) {
        U  I1535 = 0;
        if (fScalarIsForced) {
            I1535 = 29;
        }
        else if (fScalarIsReleased) {
            I1535 = 30;
        }
        if ((fScalarIsForced || fScalarIsReleased) && fRTFrcRelCbk) {
            RP  I1583 = ((void *)0);
            I1583 = (RP )(pcode + 8);
            if (I1583) {
                void * I1584 = hsimGetCbkMemOptCallback(I1583);
                if (I1584) {
                    SDaicbForHsimNoFlagFrcRel(I1584, I1535, -1, -1, -1);
                }
            }
            fScalarIsForced = 0;
            fScalarIsReleased = 0;
        }
    }
    {
        {
            RP  * I665 = ((void *)0);
            I665 = (RP  *)(pcode + 8);
            if (I665) {
                RP  I1649 = *I665;
                if (I1649) {
                    hsimDispatchNoDynElabS(I665, val, 0U);
                }
            }
        }
    }
    {
        RmaNbaGate1  * I1549 = (RmaNbaGate1  *)(pcode + 16);
        U  I1550 = (((I1549->I59) >> (16)) & ((1 << (1)) - 1));
        scalar  I1138 = X4val[val];
        if (I1550) {
            I1549->I1145.I777 = (void *)((RP )(((RP )(I1549->I1145.I777) & ~0x3)) | (I1138));
        }
        else {
            I1549->I1145.I778.I753 = I1138;
        }
        NBA_Semiler(0, &I1549->I1145);
    }
}
void  rmaPropagate13_simv_daidir (UB  * pcode, scalar  val)
{
    UB  * I1795;
    *(pcode + 0) = val;
    if (*(pcode + 1)) {
        return  ;
    }
    rmaPropagate13_p_simv_daidir(pcode, val);
    fScalarIsReleased = 0;
}
void  rmaPropagate13_f_simv_daidir (UB  * pcode, scalar  val, U  I621, scalar  * I1466, U  did)
{
    U  I1437 = 0;
    *(pcode + 1) = 1;
    fScalarIsForced = 1;
    rmaPropagate13_p_simv_daidir(pcode, val);
    fScalarIsForced = 0;
}
void  rmaPropagate13_r_simv_daidir (UB  * pcode)
{
    scalar  val;
    fScalarIsReleased = 1;
    val = *(pcode + 0);
    *(pcode + 1) = 0;
    rmaPropagate13_p_simv_daidir(pcode, val);
    fScalarIsReleased = 0;
}
void  rmaPropagate13_wn_simv_daidir (UB  * pcode, scalar  val)
{
    *(pcode + 0) = val;
    if (*(pcode + 1)) {
        return  ;
    }
    rmaPropagate13_p_simv_daidir(pcode, val);
    fScalarIsReleased = 0;
}
void  rmaPropagate34_p_simv_daidir (UB  * pcode, scalar  val)
{
    if (*(pcode + 2) == val) {
        if (fRTFrcRelCbk) {
            U  I1535 = 0;
            if (fScalarIsForced) {
                I1535 = 29;
            }
            else if (fScalarIsReleased) {
                I1535 = 30;
            }
            {
                if (fScalarIsForced || fScalarIsReleased) {
                    U  ** I1580 = (U  **)(pcode + 16);
                    U  I1581 = !(((UP )(*I1580)) & 1);
                    if (I1581) {
                        if (*I1580) {
                            SDaicbForHsimNoFlagDynElabFrcRel(*I1580, I1535, -1, -1, -1);
                        }
                    }
                    fScalarIsForced = 0;
                    fScalarIsReleased = 0;
                }
            }
        }
        return  ;
    }
    *(pcode + 2) = val;
    if (fRTFrcRelCbk) {
        U  I1535 = 0;
        if (fScalarIsForced) {
            I1535 = 29;
        }
        else if (fScalarIsReleased) {
            I1535 = 30;
        }
        {
            if (fScalarIsForced || fScalarIsReleased) {
                U  ** I1580 = (U  **)(pcode + 16);
                U  I1581 = !(((UP )(*I1580)) & 1);
                if (I1581) {
                    if (*I1580) {
                        SDaicbForHsimNoFlagDynElabFrcRel(*I1580, I1535, -1, -1, -1);
                    }
                }
                fScalarIsForced = 0;
                fScalarIsReleased = 0;
            }
        }
    }
    {
        {
            U  ** I1648 = (U  **)(pcode + 8);
            {
                U  ** I1651 = (U  **)(pcode + 16);
                if (!(((UP )(*I1651)) & 1) || !(((UP )(*I1648)) & 1)) {
                    hsimDispatchDynElabS(I1648, I1651, val, fScalarIsForced, fScalarIsReleased, 0U);
                }
            }
        }
    }
    {
        RmaNbaGate1  * I1549 = (RmaNbaGate1  *)(pcode + 24);
        U  I1550 = (((I1549->I59) >> (16)) & ((1 << (1)) - 1));
        scalar  I1138 = X4val[val];
        if (I1550) {
            I1549->I1145.I777 = (void *)((RP )(((RP )(I1549->I1145.I777) & ~0x3)) | (I1138));
        }
        else {
            I1549->I1145.I778.I753 = I1138;
        }
        NBA_Semiler(0, &I1549->I1145);
    }
}
void  rmaPropagate34_simv_daidir (UB  * pcode, scalar  val)
{
    UB  * I1795;
    *(pcode + 0) = val;
    if (*(pcode + 1)) {
        return  ;
    }
    rmaPropagate34_p_simv_daidir(pcode, val);
    fScalarIsReleased = 0;
}
void  rmaPropagate34_f_simv_daidir (UB  * pcode, scalar  val, U  I621, scalar  * I1466, U  did)
{
    U  I1437 = 0;
    *(pcode + 1) = 1;
    fScalarIsForced = 1;
    rmaPropagate34_p_simv_daidir(pcode, val);
    fScalarIsForced = 0;
}
void  rmaPropagate34_r_simv_daidir (UB  * pcode)
{
    scalar  val;
    fScalarIsReleased = 1;
    val = *(pcode + 0);
    *(pcode + 1) = 0;
    rmaPropagate34_p_simv_daidir(pcode, val);
    fScalarIsReleased = 0;
}
void  rmaPropagate34_wn_simv_daidir (UB  * pcode, scalar  val)
{
    *(pcode + 0) = val;
    if (*(pcode + 1)) {
        return  ;
    }
    rmaPropagate34_p_simv_daidir(pcode, val);
    fScalarIsReleased = 0;
}
#ifdef __cplusplus
extern "C" {
#endif
void SinitHsimPats(void);
#ifdef __cplusplus
}
#endif
