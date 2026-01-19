# STEP2 TB 시나리오 문서

## 목적
- 스케줄러의 공정성(fairness) 및 성능(throughput/latency)을 비교 가능하도록 시나리오별 테스트벤치를 분리한다.
- 기존 TB는 요청-응답 순차 구조이므로, 동시 요청이 누적되는 트래픽을 별도 TB로 구성한다.

## 파일명 규칙
- 시나리오 TB: `SAL_TB_SCN_*.sv`
- 문서: `STEP2/SIM/TB/README_TB.md`
- 공통 코드: `STEP2/SIM/TB/SAL_TB_COMMON.svh` (클럭/리셋, DUT 연결, 계측 유틸)

## 시나리오 목록(제안)
- `STEP2/SIM/TB/SAL_TB_SCN_ROW_HIT.sv`
  - 동일 row 연속 접근(높은 지역성, 최대 처리량 기대)
- `STEP2/SIM/TB/SAL_TB_SCN_ROW_CONFLICT.sv`
  - 동일 bank에서 row를 번갈아 접근(PRE/ACT 스트레스)
- `STEP2/SIM/TB/SAL_TB_SCN_BANK_INTERLEAVE.sv`
  - bank를 스트라이드로 순환(은행 병렬성 최대화)
- `STEP2/SIM/TB/SAL_TB_SCN_RANDOM.sv`
  - 주소 균일 랜덤(낮은 지역성, 일반적 worst-case)
- `STEP2/SIM/TB/SAL_TB_SCN_HOTSPOT.sv`
  - 특정 bank/row로 편중(공정성/기아 스트레스)
- `STEP2/SIM/TB/SAL_TB_SCN_RW_MIX.sv`
  - R/W 혼합 트래픽(예: 50/50 또는 80/20)
- `STEP2/SIM/TB/SAL_TB_SCN_FAIRNESS.sv`
  - 한 ID의 장기 스트림 + 다수 단발 요청(기아/공정성 관찰)

## 공통 측정 지표(권장)
- 처리량(throughput): 완료된 요청 수 / 시뮬레이션 시간
- 평균 지연(latency mean): 요청 발행~완료 사이 평균
- 99p 지연(latency p99): tail latency
- 최악 지연(latency max): starvation 여부 관찰
- 공정성(Jain’s fairness): per-ID 또는 per-bank 완료율 기반
- (옵션) row hit rate, bank utilization

## 측정 방식(권장)
- TB 내부에서 타임스탬프/카운터로 직접 계산 후 로그/CSV 출력.
- read 지연은 `AR handshake -> 마지막 R beat` 기준이 가장 명확.
- write 지연은 현재 구현이 posted 방식(B 응답이 실제 DRAM 완료보다 앞서 발생)이라,
  쓰기 지연은 참고 지표로만 사용하거나 scheduler grant 기준 지연을 함께 기록하는 것을 권장.

## 실행/선택 방법
- `script/filelist_step2.f`에는 TB가 하나만 포함되도록 관리.
- 시나리오 교체 시 해당 TB 파일만 filelist에 포함하거나,
  시나리오별로 별도 filelist를 만들어 사용.

## 시나리오별 컴파일/시뮬레이션 스크립트
- 파일명 규칙
  - compile: `script/run.compile_scn_<name>`
  - sim: `script/run.sim_scn_<name>`
  - filelist: `script/filelist_step2_scn_<name>.f`
  - output: `script/OUTPUT_STEP2_<SCN>`
- name 목록: `row_hit`, `row_conflict`, `bank_interleave`, `random`, `hotspot`, `rw_mix`, `fairness`
- 실행 위치: `script/` 디렉터리에서 실행(예: `./run.compile_scn_row_hit`)
- 로그 저장 위치: `script/LOGS/sim_<SCN>.log`

## 스케줄러 변경용 스크립트
- 스케줄러 종류
  - `fcfs`: `STEP2/RTL/SAL_SCHED.sv` (기본 FR-FCFS)
  - `cas_cnt`: `STEP2/RTL/SAL_SCHED_CAS_CNT_0120.sv` (CAS 연속 제한)
  - `rr`: `STEP2/RTL/SAL_SCHED_RR.sv` (round-robin)
  - `ref_v0`: `STEP2/RTL/SAL_SCHED_REF_V0.sv` (refactor base, aging/bliss/wdrain off)
  - `ref_v1`: `STEP2/RTL/SAL_SCHED_REF_V1_AGING.sv` (aging only)
  - `ref_v2`: `STEP2/RTL/SAL_SCHED_REF_V2_AGING_BLISS.sv` (aging + BLISS)
  - `ref_v3`: `STEP2/RTL/SAL_SCHED_REF_V3_FINAL.sv` (aging + BLISS + write-drain)
- 기준선(baseline)으로는 `rr` 사용을 권장.
- 파일명 규칙
  - compile: `script/run.compile_scn_<name>_sched_<sched>`
  - sim: `script/run.sim_scn_<name>_sched_<sched>`
- filelist: `script/filelist_step2_scn_<name>_sched_<sched>.f`
- output: `script/OUTPUT_STEP2_<SCN>_<SCHED>`
- log: `script/LOGS/sim_<SCN>_<SCHED>.log`

## 전체 배치 실행 스크립트
- 모든 시나리오 x 모든 스케줄러 실행: `script/run.all_scn_sched`

## 결과 정리 가이드
- 동일 workload/seed로 베이스라인 vs 공정성 버전 비교.
- 표/그래프로 평균/99p/최악 지연과 공정성 지표를 병기.
- 차이가 작을 경우 “시도했으나 유의미한 차이 없음”과 원인(워크로드 특성, 타이밍 제약)을 함께 기술.
