# 다른 에이전트용 지시서

## 목적
- DDR2 컨트롤러 스케줄러(SCHED) 버전별 성능/공정성 비교 실험 수행
- 시나리오별 TB와 스케줄러 조합을 자동으로 컴파일/시뮬레이션

## 환경/의존성
- `bash` 실행 환경 필요 (Linux/WSL/Git Bash 권장)
- 시뮬레이터: Synopsys VCS 사용 (기본 설정)
  - 다른 시뮬레이터 사용 시 `script/common.sh`의 `COMPILE_CMD`/옵션 수정

## 클론 & 준비
```bash
git clone <REPO_URL>
cd DDR2_Memory_Controller
```

## 시나리오/스케줄러 개요
### 시나리오 TB
`STEP2/SIM/TB/SAL_TB_SCN_*.sv`
- row_hit, row_conflict, bank_interleave, random, hotspot, rw_mix, fairness

### 스케줄러 버전
기존 스케줄러(유지):
- `fcfs`: `STEP2/RTL/SAL_SCHED.sv`
- `cas_cnt`: `STEP2/RTL/SAL_SCHED_CAS_CNT_0120.sv`
- `rr` (baseline): `STEP2/RTL/SAL_SCHED_RR.sv`

리팩토링 버전(추가):
- `ref_v0`: `STEP2/RTL/SAL_SCHED_REF_V0.sv` (aging/bliss/wdrain off)
- `ref_v1`: `STEP2/RTL/SAL_SCHED_REF_V1_AGING.sv`
- `ref_v2`: `STEP2/RTL/SAL_SCHED_REF_V2_AGING_BLISS.sv`
- `ref_v3`: `STEP2/RTL/SAL_SCHED_REF_V3_FINAL.sv`

## 실행 방법
### 단일 조합 실행
```bash
cd script
./run.compile_scn_row_hit_sched_rr
./run.sim_scn_row_hit_sched_rr
```

### 전체 배치 실행(모든 시나리오 x 모든 스케줄러)
```bash
cd script
./run.all_scn_sched
```

## 출력/로그 위치
- 컴파일/시뮬레이션 출력: `script/OUTPUT_STEP2_<SCN>_<SCHED>`
- 시뮬레이션 로그: `script/LOGS/sim_<SCN>_<SCHED>.log`

## 유의 사항
- `SAL_SCHED` 모듈명이 동일하므로 **filelist에 스케줄러 파일 1개만** 포함되어야 함.
  - 이 작업은 `script/filelist_step2_scn_*_sched_*.f`가 처리함.
- baseline 비교는 `rr` 기준으로 진행 권장.
- write 지연은 posted 방식이라 참고 지표로만 사용 권장(문서/로그 참고).

## 참고 문서
- TB 시나리오 설명: `STEP2/SIM/TB/README_TB.md`
- 스크립트 사용법: `script/README.md`
