# DDR2 Memory Controller (SystemVerilog)

![Language](https://img.shields.io/badge/Language-SystemVerilog-1f6feb)
![Target](https://img.shields.io/badge/Target-DDR2-0e8a16)
![Protocol](https://img.shields.io/badge/Protocol-AXI%20%2F%20APB-ff8c00)
![PHY](https://img.shields.io/badge/PHY-DFI-555)

SystemVerilog 기반 DDR2 컨트롤러 학습/구현 프로젝트입니다. DRAM 동작 원리를 이해하고, 타이밍 제약을 만족하는 스케줄링과 PHY 인터페이스 설계를 목표로 합니다.

![Overview](DOC/FIG/Overview.png)
![Block Diagram](DOC/FIG/Block_diagram.png)

## 목차
- [프로젝트 개요](#프로젝트-개요)
- [핵심 기능](#핵심-기능)
- [아키텍처 요약](#아키텍처-요약)
- [프로토콜 및 스펙](#프로토콜-및-스펙)
- [타이밍 파라미터](#타이밍-파라미터)
- [Row Open 정책](#row-open-정책)
- [Read Out-of-Order 처리](#read-out-of-order-처리)
- [시뮬레이션 실행](#시뮬레이션-실행)
- [디렉터리 구조](#디렉터리-구조)
- [라이선스](#라이선스)

## 프로젝트 개요
- APB로 컨트롤러 설정(타이밍 파라미터, 상태/디버그 레지스터 등)
- AXI로 DRAM 접근 요청 수신
- 요청을 스케줄링하고 DDR2 명령으로 변환하여 DDRPHY로 전달
- DDRPHY가 서브-사이클 타이밍을 만족하도록 신호를 제어

## 핵심 기능
- AMBA AXI/APB 기반 인터페이스
- DDR2 커맨드 스케줄링 및 타이밍 제약 검증
- DFI(단순화 버전) 기반 DDRPHY 연결
- Row Open 정책 및 타이밍 카운터 관리
- 동일 ID 순서 보장을 위한 Read Out-of-Order 제어

## 아키텍처 요약
- 컨트롤러는 AXI 요청을 수신하고, 내부 스케줄러가 DRAM 명령으로 변환합니다.
- APB는 설정/상태 레지스터 접근에 사용됩니다.
- DDRPHY는 컨트롤러의 커맨드 타이밍을 물리 계층 신호로 정밀 변환합니다.

## 프로토콜 및 스펙
- AMBA AXI/APB: 온칩 인터커넥트 표준
- DFI: 컨트롤러-DDRPHY 간 표준 인터페이스(단순화 버전 사용)
- DDR2: JEDEC JESD79-2F
- 참고 문서: `DOC/` 디렉터리 내 AMBA/DDR2 관련 문서

## 타이밍 파라미터
### ACT/REF 전에 만족해야 하는 조건
- (Intra-bank) `tRC`, `tRP`, `tRFC`
- (Inter-bank) `tRRD`, `tFAW`

### READ 전에 만족해야 하는 조건
- (Intra-bank) `tRCD`, `tWTR` (자세히: `(CL-1) + (BL/2) + tWTR`)
- (Inter-bank) `tCCD`

### WRITE 전에 만족해야 하는 조건
- (Intra-bank) `tRCD`
- (Inter-bank) `tCCD`

### PRECHARGE 전에 만족해야 하는 조건
- (Intra-bank) `tRAS (min)`, `tRTP`, `tWR`

## Row Open 정책
- 동일 Row 재접근 성능을 위해 `ROW_OPEN_CNT` 사이클 동안 Row를 유지합니다.
- Row hit 시 카운터를 리셋하여 Row를 더 오래 유지합니다.
- Row miss 또는 카운터 만료 시 Row를 닫습니다.

## Read Out-of-Order 처리
- AXI는 동일 ID 요청에 대해 in-order 서비스가 필요합니다.
- 서로 다른 ID는 out-of-order 처리가 가능합니다.
- 각 요청에 ID별 시퀀스 번호를 부여하여, 마지막 스케줄 번호 + 1을 넘는 RD 명령은 지연합니다.

## 시뮬레이션 실행
`script` 폴더에 VCS/Verdi 기반 실행 스크립트가 있습니다. (Linux/WSL 환경 권장)

```bash
cd script
./run.compile 1   # STEP1 컴파일
./run.sim 1       # STEP1 시뮬레이션

./run.compile 2   # STEP2 컴파일
./run.sim 2       # STEP2 시뮬레이션

./run.verdi 2     # 파형/디버깅
```

## 디렉터리 구조
```
DOC/            # 스펙/레퍼런스 문서, 그림
STEP1/          # 1단계 RTL/SIM
STEP2/          # 2단계 RTL/SIM
script/         # 컴파일/시뮬레이션 스크립트
LICENSE
README.md
```

## 라이선스
라이선스는 `LICENSE`를 참고하세요.
