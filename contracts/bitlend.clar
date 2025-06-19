;; Title: BitLend - Decentralized Bitcoin-Collateralized Lending Protocol
;;
;; Summary: A trustless lending platform enabling users to borrow against 
;;          Bitcoin and STX collateral with automated liquidation protection
;;
;; Description: BitLend revolutionizes DeFi lending by creating a secure,
;;              decentralized marketplace where users can deposit Bitcoin as
;;              collateral to access instant liquidity. The protocol features
;;              dynamic risk management, real-time price oracles, and automated
;;              liquidation mechanisms to protect both lenders and borrowers.
;;
;; Key Features:
;; - Multi-asset collateral support (BTC, STX)
;; - Configurable collateral ratios and liquidation thresholds
;; - Real-time interest calculation and compounding
;; - Automated liquidation protection system
;; - Comprehensive borrower portfolio tracking
;; - Oracle-based price feed integration

;; CONSTANTS & ERROR CODES

;; Authorization Constants
(define-constant CONTRACT-OWNER tx-sender)

;; Error Codes - Authorization & Access Control
(define-constant ERR-NOT-AUTHORIZED (err u100))

;; Error Codes - Lending Operations
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-BELOW-MINIMUM (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-LOAN-NOT-FOUND (err u107))
(define-constant ERR-LOAN-NOT-ACTIVE (err u108))
(define-constant ERR-INVALID-LOAN-ID (err u109))

;; Error Codes - System State
(define-constant ERR-ALREADY-INITIALIZED (err u104))
(define-constant ERR-NOT-INITIALIZED (err u105))
(define-constant ERR-INVALID-LIQUIDATION (err u106))

;; Error Codes - Validation
(define-constant ERR-INVALID-PRICE (err u110))
(define-constant ERR-INVALID-ASSET (err u111))
(define-constant ERR-ARITHMETIC-OVERFLOW (err u112))

;; Protocol Configuration
(define-constant VALID-ASSETS (list "BTC" "STX"))
(define-constant MAX-LOANS-PER-USER u10)
(define-constant BLOCKS-PER-DAY u144)
(define-constant MAX-PRICE-VALUE u1000000000000)
(define-constant MIN-COLLATERAL-RATIO u110)

;; DATA VARIABLES

;; Platform State Management
(define-data-var platform-initialized bool false)
(define-data-var platform-paused bool false)

;; Risk Management Parameters
(define-data-var minimum-collateral-ratio uint u150) ;; 150% minimum collateral
(define-data-var liquidation-threshold uint u120) ;; 120% liquidation trigger
(define-data-var platform-fee-rate uint u100) ;; 1% platform fee (100 basis points)
(define-data-var base-interest-rate uint u500) ;; 5% base interest rate

;; Platform Analytics
(define-data-var total-btc-locked uint u0)
(define-data-var total-stx-locked uint u0)
(define-data-var total-loans-issued uint u0)
(define-data-var total-value-borrowed uint u0)
(define-data-var protocol-revenue uint u0)

;; DATA MAPS

;; Core Loan Registry
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    collateral-asset: (string-ascii 3),
    collateral-amount: uint,
    loan-amount: uint,
    interest-rate: uint,
    start-height: uint,
    last-interest-calc: uint,
    accumulated-interest: uint,
    status: (string-ascii 20),
  }
)

;; User Portfolio Tracking
(define-map user-loans
  { user: principal }
  {
    active-loans: (list 10 uint),
    total-borrowed: uint,
    total-collateral: uint,
  }
)