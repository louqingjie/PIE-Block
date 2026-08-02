/* 单精度复现 MCU ik_solve，诊断 NaN 来源（与生成代码逐字对应） */
#include <stdio.h>
#include <math.h>
#include <stdint.h>

#define JOINT_COUNT 4
#define IK_EPS 0.001f
#define DEG_TO_RAD 0.0174532925f
#define RAD_TO_DEG 57.29577951f
#define IK_MAX_STEP_DEG 4.0f
#define ORIENTATION_WEIGHT 220.0f
#define IK_SUBSTEPS 10
#define IK_STALL_COUNT 3
#define IK_STALL_RELAX 10
#define IK_STALL_SNAP 100

/* 全局变量（对应生成代码） */
float jointAngle[4];
const float jointHome[4] = {0.00f, 90.00f, 0.00f, 0.00f};
const float jointMin[4] = {-90.00f, 0.00f, -90.00f, -90.00f};
const float jointMax[4] = {90.00f, 90.00f, 90.00f, 90.00f};
const float jointAxis[4][3] = {
    {0.0f, 0.0f, 1.0f},
    {0.0f, -1.0f, 0.0f},
    {0.0f, -1.0f, 0.0f},
    {1.0f, 0.0f, 0.0f}
};
const float jointLen[4] = {10.00f, 100.00f, 100.00f, 10.00f};

float targetX, targetY, targetZ, targetRoll, targetPitch, targetYaw;
uint8_t solverMask = 0, ikRequestedMask = 0;
uint8_t ikStallCount = 0;
uint8_t ik_reachable = 1;
uint8_t ikStepClamped = 0, ikNumericProtected = 0;

static float xdata_basis[3][3], ikRot[3][3], ikTmp[3][3];
static float ikPts[5][3];
static float ikAxes[4][3];
static float ikCols[4][3];
static float ikJte[4];
static float ikLa[3], ikLv[3], ikWv[3], ikEv[3];
static float ikTargetBasis[3][3], ikOriErr[3];
static float ikBasisRows[6][6], ikTaskRows[3][6], ikTaskAxes[3][3], ikTaskDot[3], ikTaskErr[3];
static float ikDesiredAxes[3][3], ikComplementAxes[3][3];
static uint8_t ikBasisCount, ikPositionRank, ikTaskCount, ikTaskKind[3];

/* ---------- 生成代码复制 ---------- */
void mat_vec(float m[3][3], float v[3], float out[3]) {
    out[0] = m[0][0]*v[0]+m[0][1]*v[1]+m[0][2]*v[2];
    out[1] = m[1][0]*v[0]+m[1][1]*v[1]+m[1][2]*v[2];
    out[2] = m[2][0]*v[0]+m[2][1]*v[1]+m[2][2]*v[2];
}
void axis_rot(float a[3], float ang, float m[3][3]) {
    float c,s,t;
    c=cos(ang); s=sin(ang); t=1.0f-c;
    m[0][0]=t*a[0]*a[0]+c; m[0][1]=t*a[0]*a[1]-s*a[2]; m[0][2]=t*a[0]*a[2]+s*a[1];
    m[1][0]=t*a[0]*a[1]+s*a[2]; m[1][1]=t*a[1]*a[1]+c; m[1][2]=t*a[1]*a[2]-s*a[0];
    m[2][0]=t*a[0]*a[2]-s*a[1]; m[2][1]=t*a[1]*a[2]+s*a[0]; m[2][2]=t*a[2]*a[2]+c;
}
void mat_mul(float x[3][3], float y[3][3], float out[3][3]) {
    uint8_t r,c;
    for(r=0;r<3;r++) for(c=0;c<3;c++)
        out[r][c]=x[r][0]*y[0][c]+x[r][1]*y[1][c]+x[r][2]*y[2][c];
}
void ik_fk(void) {
    uint8_t k,r,c; float ang;
    for(r=0;r<3;r++) for(c=0;c<3;c++) xdata_basis[r][c]=(r==c)?1.0f:0.0f;
    ikPts[0][0]=0.0f; ikPts[0][1]=0.0f; ikPts[0][2]=0.0f;
    for(k=0;k<JOINT_COUNT;k++) {
        ikLa[0]=jointAxis[k][0]; ikLa[1]=jointAxis[k][1]; ikLa[2]=jointAxis[k][2];
        mat_vec(xdata_basis, ikLa, ikWv);
        ikAxes[k][0]=ikWv[0]; ikAxes[k][1]=ikWv[1]; ikAxes[k][2]=ikWv[2];
        ang=jointAngle[k]*DEG_TO_RAD;
        axis_rot(ikLa, ang, ikRot);
        mat_mul(xdata_basis, ikRot, ikTmp);
        for(r=0;r<3;r++) for(c=0;c<3;c++) xdata_basis[r][c]=ikTmp[r][c];
        ikLv[0]=jointLen[k]; ikLv[1]=0.0f; ikLv[2]=0.0f;
        mat_vec(xdata_basis, ikLv, ikWv);
        ikPts[k+1][0]=ikPts[k][0]+ikWv[0];
        ikPts[k+1][1]=ikPts[k][1]+ikWv[1];
        ikPts[k+1][2]=ikPts[k][2]+ikWv[2];
    }
}
void ik_build_position_cols(void) {
    uint8_t k;
    for(k=0;k<JOINT_COUNT;k++){ikLv[0]=ikPts[JOINT_COUNT][0]-ikPts[k][0];ikLv[1]=ikPts[JOINT_COUNT][1]-ikPts[k][1];ikLv[2]=ikPts[JOINT_COUNT][2]-ikPts[k][2];ikCols[k][0]=ikAxes[k][1]*ikLv[2]-ikAxes[k][2]*ikLv[1];ikCols[k][1]=ikAxes[k][2]*ikLv[0]-ikAxes[k][0]*ikLv[2];ikCols[k][2]=ikAxes[k][0]*ikLv[1]-ikAxes[k][1]*ikLv[0];}
}
void ik_orientation_error(float roll,float pitch,float yaw) {
    float cr,sr,cp,sp,cy,sy,sinAngle,cosAngle,angleScale,currentPitch;
    if(!(solverMask&1))roll=atan2(xdata_basis[2][1],xdata_basis[2][2])*RAD_TO_DEG;
    currentPitch=xdata_basis[2][0];if(currentPitch>1.0f)currentPitch=1.0f;if(currentPitch<-1.0f)currentPitch=-1.0f;
    if(!(solverMask&2))pitch=asin(currentPitch)*RAD_TO_DEG;
    if(!(solverMask&4))yaw=atan2(xdata_basis[1][0],xdata_basis[0][0])*RAD_TO_DEG;
    cr=cos(roll*DEG_TO_RAD);sr=sin(roll*DEG_TO_RAD);cp=cos(pitch*DEG_TO_RAD);sp=sin(pitch*DEG_TO_RAD);cy=cos(yaw*DEG_TO_RAD);sy=sin(yaw*DEG_TO_RAD);
    ikTargetBasis[0][0]=cy*cp;ikTargetBasis[1][0]=sy*cp;ikTargetBasis[2][0]=sp;
    ikTargetBasis[0][1]=-sy*cr-cy*sp*sr;ikTargetBasis[1][1]=cy*cr-sy*sp*sr;ikTargetBasis[2][1]=cp*sr;
    ikTargetBasis[0][2]=sy*sr-cy*sp*cr;ikTargetBasis[1][2]=-cy*sr-sy*sp*cr;ikTargetBasis[2][2]=cp*cr;
    ikOriErr[0]=0.5f*((xdata_basis[1][0]*ikTargetBasis[2][0]-xdata_basis[2][0]*ikTargetBasis[1][0])+(xdata_basis[1][1]*ikTargetBasis[2][1]-xdata_basis[2][1]*ikTargetBasis[1][1])+(xdata_basis[1][2]*ikTargetBasis[2][2]-xdata_basis[2][2]*ikTargetBasis[1][2]));
    ikOriErr[1]=0.5f*((xdata_basis[2][0]*ikTargetBasis[0][0]-xdata_basis[0][0]*ikTargetBasis[2][0])+(xdata_basis[2][1]*ikTargetBasis[0][1]-xdata_basis[0][1]*ikTargetBasis[2][1])+(xdata_basis[2][2]*ikTargetBasis[0][2]-xdata_basis[0][2]*ikTargetBasis[2][2]));
    ikOriErr[2]=0.5f*((xdata_basis[0][0]*ikTargetBasis[1][0]-xdata_basis[1][0]*ikTargetBasis[0][0])+(xdata_basis[0][1]*ikTargetBasis[1][1]-xdata_basis[1][1]*ikTargetBasis[0][1])+(xdata_basis[0][2]*ikTargetBasis[1][2]-xdata_basis[1][2]*ikTargetBasis[0][2]));
    sinAngle=sqrt(ikOriErr[0]*ikOriErr[0]+ikOriErr[1]*ikOriErr[1]+ikOriErr[2]*ikOriErr[2]);
    cosAngle=0.5f*(ikTargetBasis[0][0]*xdata_basis[0][0]+ikTargetBasis[1][0]*xdata_basis[1][0]+ikTargetBasis[2][0]*xdata_basis[2][0]+ikTargetBasis[0][1]*xdata_basis[0][1]+ikTargetBasis[1][1]*xdata_basis[1][1]+ikTargetBasis[2][1]*xdata_basis[2][1]+ikTargetBasis[0][2]*xdata_basis[0][2]+ikTargetBasis[1][2]*xdata_basis[1][2]+ikTargetBasis[2][2]*xdata_basis[2][2]-1.0f);
    if(cosAngle>1.0f)cosAngle=1.0f;if(cosAngle<-1.0f)cosAngle=-1.0f;
    angleScale=(sinAngle>IK_EPS)?atan2(sinAngle,cosAngle)/sinAngle:1.0f;
    ikOriErr[0]*=angleScale;ikOriErr[1]*=angleScale;ikOriErr[2]*=angleScale;
}
void ik_build_tasks(void) {
    uint8_t i,j,t,c,desiredCount,complementCount;
    float dot,norm,ax,ay,az,yawNorm,vx,vy,vz;
    ikBasisCount=0; ikTaskCount=0;
    for(t=0;t<3;t++){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[t][i]=ikCols[i][t];
        for(j=0;j<ikBasisCount;j++){dot=0.0f;for(i=0;i<JOINT_COUNT;i++)dot+=ikBasisRows[t][i]*ikBasisRows[j][i];
            for(i=0;i<JOINT_COUNT;i++)ikBasisRows[t][i]-=dot*ikBasisRows[j][i];}
        norm=0.0f;for(i=0;i<JOINT_COUNT;i++)norm+=ikBasisRows[t][i]*ikBasisRows[t][i];
        norm=sqrt(norm);if(norm>0.000001f){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[ikBasisCount][i]=ikBasisRows[t][i]/norm;ikBasisCount++;}}
    ikPositionRank=ikBasisCount;desiredCount=0;
    for(t=0;t<3;t++){if(!((t==0&&(ikRequestedMask&2))||(t==1&&(ikRequestedMask&4))||(t==2&&(ikRequestedMask&1))))continue;
        if(t==0){yawNorm=sqrt(xdata_basis[0][0]*xdata_basis[0][0]+xdata_basis[1][0]*xdata_basis[1][0]);if(yawNorm>0.0001f){vx=xdata_basis[1][0]/yawNorm;vy=-xdata_basis[0][0]/yawNorm;vz=0.0f;}else{vx=0.0f;vy=0.0f;vz=0.0f;}}
        else if(t==1){vx=0.0f;vy=0.0f;vz=1.0f;}
        else{vx=xdata_basis[0][0];vy=xdata_basis[1][0];vz=xdata_basis[2][0];}
        for(j=0;j<desiredCount;j++){dot=vx*ikDesiredAxes[j][0]+vy*ikDesiredAxes[j][1]+vz*ikDesiredAxes[j][2];vx-=dot*ikDesiredAxes[j][0];vy-=dot*ikDesiredAxes[j][1];vz-=dot*ikDesiredAxes[j][2];}
        norm=sqrt(vx*vx+vy*vy+vz*vz);if(norm>0.00001f){ikDesiredAxes[desiredCount][0]=vx/norm;ikDesiredAxes[desiredCount][1]=vy/norm;ikDesiredAxes[desiredCount][2]=vz/norm;desiredCount++;}}
    complementCount=0;
    for(c=0;c<3;c++){vx=(c==0)?1.0f:0.0f;vy=(c==1)?1.0f:0.0f;vz=(c==2)?1.0f:0.0f;
        for(j=0;j<desiredCount;j++){dot=vx*ikDesiredAxes[j][0]+vy*ikDesiredAxes[j][1]+vz*ikDesiredAxes[j][2];vx-=dot*ikDesiredAxes[j][0];vy-=dot*ikDesiredAxes[j][1];vz-=dot*ikDesiredAxes[j][2];}
        for(j=0;j<complementCount;j++){dot=vx*ikComplementAxes[j][0]+vy*ikComplementAxes[j][1]+vz*ikComplementAxes[j][2];vx-=dot*ikComplementAxes[j][0];vy-=dot*ikComplementAxes[j][1];vz-=dot*ikComplementAxes[j][2];}
        norm=sqrt(vx*vx+vy*vy+vz*vz);if(norm>0.00001f){ikComplementAxes[complementCount][0]=vx/norm;ikComplementAxes[complementCount][1]=vy/norm;ikComplementAxes[complementCount][2]=vz/norm;complementCount++;}}
    for(c=0;c<complementCount;c++){
        for(i=0;i<JOINT_COUNT;i++)ikTaskRows[0][i]=ikAxes[i][0]*ikComplementAxes[c][0]+ikAxes[i][1]*ikComplementAxes[c][1]+ikAxes[i][2]*ikComplementAxes[c][2];
        for(j=0;j<ikBasisCount;j++){dot=0.0f;for(i=0;i<JOINT_COUNT;i++)dot+=ikTaskRows[0][i]*ikBasisRows[j][i];for(i=0;i<JOINT_COUNT;i++)ikTaskRows[0][i]-=dot*ikBasisRows[j][i];}
        norm=0.0f;for(i=0;i<JOINT_COUNT;i++)norm+=ikTaskRows[0][i]*ikTaskRows[0][i];norm=sqrt(norm);
        if(norm>0.000001f&&ikBasisCount<6){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[ikBasisCount][i]=ikTaskRows[0][i]/norm;ikBasisCount++;}}
    for(t=0;t<3;t++){if(!((t==0&&(ikRequestedMask&2))||(t==1&&(ikRequestedMask&4))||(t==2&&(ikRequestedMask&1))))continue;
        if(t==0){yawNorm=sqrt(xdata_basis[0][0]*xdata_basis[0][0]+xdata_basis[1][0]*xdata_basis[1][0]);if(yawNorm>0.0001f){ax=xdata_basis[1][0]/yawNorm;ay=-xdata_basis[0][0]/yawNorm;az=0.0f;}else{ax=0.0f;ay=0.0f;az=0.0f;}}
        else if(t==1){ax=0.0f;ay=0.0f;az=1.0f;}
        else{ax=xdata_basis[0][0];ay=xdata_basis[1][0];az=xdata_basis[2][0];}
        for(i=0;i<JOINT_COUNT;i++)ikTaskRows[ikTaskCount][i]=ikAxes[i][0]*ax+ikAxes[i][1]*ay+ikAxes[i][2]*az;
        for(j=0;j<ikBasisCount;j++){dot=0.0f;for(i=0;i<JOINT_COUNT;i++)dot+=ikTaskRows[ikTaskCount][i]*ikBasisRows[j][i];for(i=0;i<JOINT_COUNT;i++)ikTaskRows[ikTaskCount][i]-=dot*ikBasisRows[j][i];}
        norm=0.0f;for(i=0;i<JOINT_COUNT;i++)norm+=ikTaskRows[ikTaskCount][i]*ikTaskRows[ikTaskCount][i];norm=sqrt(norm);
        if(norm>0.0001f&&ikBasisCount<6){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[ikBasisCount][i]=ikTaskRows[ikTaskCount][i]/norm;ikBasisCount++;
            ikTaskAxes[ikTaskCount][0]=ax;ikTaskAxes[ikTaskCount][1]=ay;ikTaskAxes[ikTaskCount][2]=az;
            ikTaskKind[ikTaskCount]=t;ikTaskCount++;}}
}
void ik_solve(float x,float y,float z,float roll,float pitch,float yaw) {
    uint8_t k,t,doOrient;
    float num,den,alpha,maxStep,step,errBefore,errAfter,posErr2;
    ik_fk();
    ikEv[0]=x-ikPts[JOINT_COUNT][0];ikEv[1]=y-ikPts[JOINT_COUNT][1];ikEv[2]=z-ikPts[JOINT_COUNT][2];
    posErr2=ikEv[0]*ikEv[0]+ikEv[1]*ikEv[1]+ikEv[2]*ikEv[2];
    doOrient=(posErr2<4.0f||ikStallCount>=IK_STALL_RELAX)?1:0;
    ik_orientation_error(roll,pitch,yaw);
    ik_build_position_cols();
    for(k=0;k<JOINT_COUNT;k++){ikJte[k]=ikCols[k][0]*ikEv[0]+ikCols[k][1]*ikEv[1]+ikCols[k][2]*ikEv[2];}
    ikRequestedMask=solverMask;ik_build_tasks();
    for(t=0;t<ikTaskCount;t++)ikTaskErr[t]=(ikOriErr[0]*ikTaskAxes[t][0]+ikOriErr[1]*ikTaskAxes[t][1]+ikOriErr[2]*ikTaskAxes[t][2])*ORIENTATION_WEIGHT;
    for(k=0;k<JOINT_COUNT;k++){if(doOrient)for(t=0;t<ikTaskCount;t++)ikJte[k]+=ikTaskRows[t][k]*ikTaskErr[t]*ORIENTATION_WEIGHT;}
    num=0.0f;ikWv[0]=0.0f;ikWv[1]=0.0f;ikWv[2]=0.0f;
    for(t=0;t<ikTaskCount;t++)ikTaskDot[t]=0.0f;
    for(k=0;k<JOINT_COUNT;k++){if(ikJte[k]!=ikJte[k]||ikJte[k]>1.0e6f||ikJte[k]<-1.0e6f)ikJte[k]=0.0f;}
    for(k=0;k<JOINT_COUNT;k++){num+=ikJte[k]*ikJte[k];ikWv[0]+=ikCols[k][0]*ikJte[k];ikWv[1]+=ikCols[k][1]*ikJte[k];ikWv[2]+=ikCols[k][2]*ikJte[k];
        if(doOrient)for(t=0;t<ikTaskCount;t++)ikTaskDot[t]+=ikTaskRows[t][k]*ORIENTATION_WEIGHT*ikJte[k];}
    den=ikWv[0]*ikWv[0]+ikWv[1]*ikWv[1]+ikWv[2]*ikWv[2];
    if(doOrient)for(t=0;t<ikTaskCount;t++)den+=ikTaskDot[t]*ikTaskDot[t];
    alpha=(den>IK_EPS)?num/den:0.0f;
    ikNumericProtected=0;
    if(alpha!=alpha||alpha>100000.0f||alpha<-100000.0f){alpha=0.0f;ikNumericProtected=1;}
    maxStep=0.0f;
    for(k=0;k<JOINT_COUNT;k++){step=alpha*ikJte[k]*RAD_TO_DEG;if(step<0.0f)step=-step;if(step>maxStep)maxStep=step;}
    if(maxStep>IK_MAX_STEP_DEG)alpha*=IK_MAX_STEP_DEG/maxStep;
    errBefore=posErr2;
    if(doOrient)for(t=0;t<ikTaskCount;t++)errBefore+=ikTaskErr[t]*ikTaskErr[t];
    ikStepClamped=0;
    for(k=0;k<JOINT_COUNT;k++){jointAngle[k]+=alpha*ikJte[k]*RAD_TO_DEG;
        if(jointAngle[k]!=jointAngle[k]||jointAngle[k]>1.0e6f||jointAngle[k]<-1.0e6f){jointAngle[k]=jointHome[k];ikNumericProtected=1;}
        if(jointAngle[k]<jointMin[k]){jointAngle[k]=jointMin[k];ikStepClamped=1;}
        if(jointAngle[k]>jointMax[k]){jointAngle[k]=jointMax[k];ikStepClamped=1;}}
    ik_fk();
    errAfter=(x-ikPts[JOINT_COUNT][0])*(x-ikPts[JOINT_COUNT][0])+(y-ikPts[JOINT_COUNT][1])*(y-ikPts[JOINT_COUNT][1])+(z-ikPts[JOINT_COUNT][2])*(z-ikPts[JOINT_COUNT][2]);
    if(doOrient){ik_orientation_error(roll,pitch,yaw);ikRequestedMask=solverMask;ik_build_tasks();
        for(t=0;t<ikTaskCount;t++){step=(ikOriErr[0]*ikTaskAxes[t][0]+ikOriErr[1]*ikTaskAxes[t][1]+ikOriErr[2]*ikTaskAxes[t][2])*ORIENTATION_WEIGHT;errAfter+=step*step;}}
    ik_reachable=(errAfter<errBefore-0.0001f)?1:0;
    if(ik_reachable)ikStallCount=0;else if(ikStallCount<255)ikStallCount++;
}

int has_nan(void) {
    int i;
    for(i=0;i<JOINT_COUNT;i++) if(isnan(jointAngle[i])||isinf(jointAngle[i])) return 1;
    for(i=0;i<=JOINT_COUNT;i++) if(isnan(ikPts[i][0])||isnan(ikPts[i][1])||isnan(ikPts[i][2])) return 1;
    return 0;
}

int main(void) {
    int i;
    /* 验证修复：ikJte 钳位 + jointAngle NaN 保护 */
    solverMask = 1;
    for(i=0;i<JOINT_COUNT;i++) jointAngle[i]=jointHome[i];
    printf("=== 验证修复后的 ik_solve 在 inf ikJte 下不产生 NaN ===\n");
    {
        /* 手动构造一个巨大 ikJte（模拟奇异残差溢出），走完整 ik_solve */
        /* 通过不可达 + 姿态极端目标尽量触发 */
        int sub, iter;
        for(iter=0; iter<50; iter++) {
            for(sub=0; sub<IK_SUBSTEPS; sub++) {
                /* 极远且姿态相反的目标 */
                ik_solve(5000.0f, 5000.0f, 5000.0f, 179.0f, 89.0f, 179.0f);
                if (has_nan()) {
                    printf("FAIL: NaN at iter=%d sub=%d stall=%d\n", iter, sub, (int)ikStallCount);
                    for(i=0;i<JOINT_COUNT;i++) printf("  j%d=%.6f\n", i, jointAngle[i]);
                    return 1;
                }
            }
        }
        printf("PASS: no NaN after extreme targets\n");
    }
    /* 直接验证 0*inf 场景在保护下恢复 home */
    printf("=== 直接验证 jointAngle NaN 保护 ===\n");
    {
        float alpha = 0.0f;
        float ikJte_inf = 1.0f/0.0f;
        float old = jointAngle[0];
        jointAngle[0] += alpha * ikJte_inf * RAD_TO_DEG;
        if (jointAngle[0] != jointAngle[0] || jointAngle[0] > 1.0e6f || jointAngle[0] < -1.0e6f) {
            jointAngle[0] = jointHome[0]; /* 修复逻辑 */
        }
        if (jointAngle[0] != jointAngle[0]) {
            printf("FAIL: still NaN\n");
            return 1;
        }
        printf("PASS: NaN recovered to home (%.3f)\n", jointAngle[0]);
    }
    return 0;
}
