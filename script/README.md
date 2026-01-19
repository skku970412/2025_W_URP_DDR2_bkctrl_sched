# Script 사용 안내

## 기본 스크립트
- `run.compile`: STEP1/STEP2 컴파일 (사용: `./run.compile 1` 또는 `./run.compile 2`)
- `run.sim`: STEP1/STEP2 시뮬레이션 (사용: `./run.sim 1` 또는 `./run.sim 2`)
- `run.verdi`: Verdi 실행
- `common.sh`: 공통 환경 설정(경로/옵션)

## 시나리오별 스크립트 (STEP2)
- compile: `run.compile_scn_<name>`
- sim: `run.sim_scn_<name>`
- filelist: `filelist_step2_scn_<name>.f`
- output: `OUTPUT_STEP2_<SCN>`
- log: `LOGS/sim_<SCN>.log`

name 목록: `row_hit`, `row_conflict`, `bank_interleave`, `random`, `hotspot`, `rw_mix`, `fairness`

## 스케줄러별 스크립트 (STEP2)
- compile: `run.compile_scn_<name>_sched_<sched>`
- sim: `run.sim_scn_<name>_sched_<sched>`
- filelist: `filelist_step2_scn_<name>_sched_<sched>.f`
- output: `OUTPUT_STEP2_<SCN>_<SCHED>`
- log: `LOGS/sim_<SCN>_<SCHED>.log`

sched 목록: `fcfs`, `cas_cnt`, `rr`

## 전체 배치 실행
- 모든 시나리오 x 모든 스케줄러: `run.all_scn_sched`

## 실행 위치
- 반드시 `script/` 디렉터리에서 실행

## 사용 예시
```bash
cd script
./run.compile_scn_row_hit
./run.sim_scn_row_hit

./run.compile_scn_row_hit_sched_rr
./run.sim_scn_row_hit_sched_rr

./run.all_scn_sched
```
