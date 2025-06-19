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

;; Oracle Price Feeds
(define-map asset-prices
  { asset: (string-ascii 3) }
  {
    price: uint,
    last-updated: uint,
    oracle: principal,
  }
)

;; Platform Access Control
(define-map authorized-oracles
  { oracle: principal }
  { authorized: bool }
)

;; PRIVATE HELPER FUNCTIONS

;; Calculate collateral-to-loan ratio with precision
(define-private (calculate-collateral-ratio
    (collateral uint)
    (loan uint)
    (asset-price uint)
  )
  (if (is-eq loan u0)
    u0
    (let (
        (collateral-value (/ (* collateral asset-price) u100000000)) ;; Adjust for 8 decimal precision
        (ratio (/ (* collateral-value u10000) loan)) ;; Return as basis points
      )
      ratio
    )
  )
)

;; Calculate compound interest with block-based precision
(define-private (calculate-compound-interest
    (principal uint)
    (rate uint)
    (blocks uint)
  )
  (if (is-eq blocks u0)
    u0
    (let (
        (daily-rate (/ rate u365)) ;; Annual rate to daily
        (block-rate (/ daily-rate BLOCKS-PER-DAY)) ;; Daily to per-block
        (simple-interest (/ (* (* principal block-rate) blocks) u10000))
      )
      simple-interest
    )
  )
)

;; Validate loan exists and is accessible
(define-private (validate-loan-access
    (loan-id uint)
    (caller principal)
  )
  (match (map-get? loans { loan-id: loan-id })
    loan (and
      (is-eq (get borrower loan) caller)
      (is-eq (get status loan) "active")
    )
    false
  )
)

;; Check if asset is supported by the protocol
(define-private (is-supported-asset (asset (string-ascii 3)))
  (is-some (index-of VALID-ASSETS asset))
)

;; Validate price feed data integrity
(define-private (is-valid-price (price uint))
  (and
    (> price u0)
    (<= price MAX-PRICE-VALUE)
  )
)

;; Safe arithmetic operations to prevent overflow
(define-private (safe-add
    (a uint)
    (b uint)
  )
  (let ((result (+ a b)))
    (if (>= result a) ;; Check for overflow
      (ok result)
      ERR-ARITHMETIC-OVERFLOW
    )
  )
)

;; Remove loan from user's active loan list
(define-private (remove-loan-from-user
    (user principal)
    (loan-id uint)
  )
  (match (map-get? user-loans { user: user })
    user-data (let (
        (current-loans (get active-loans user-data))
        (filtered-loans (fold filter-loan-helper current-loans {
          target-id: loan-id,
          result: (list),
        }))
      )
      (begin
        (map-set user-loans { user: user }
          (merge user-data { active-loans: (get result filtered-loans) })
        )
        true
      )
    )
    false
  )
)

;; Helper function for filtering loans using fold
(define-private (filter-loan-helper
    (loan-id uint)
    (acc {
      target-id: uint,
      result: (list 10 uint),
    })
  )
  (if (not (is-eq loan-id (get target-id acc)))
    (merge acc { result: (unwrap-panic (as-max-len? (append (get result acc) loan-id) u10)) })
    acc
  )
)

;; LIQUIDATION ENGINE

;; Check if position requires liquidation
(define-private (check-liquidation-eligibility (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan (match (map-get? asset-prices { asset: (get collateral-asset loan) })
      price-data (let ((current-ratio (calculate-collateral-ratio (get collateral-amount loan)
          (get loan-amount loan) (get price price-data)
        )))
        (<= current-ratio (var-get liquidation-threshold))
      )
      false
    )
    false
  )
)

;; Execute liquidation process
(define-private (execute-liquidation (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan (begin
      ;; Update loan status
      (map-set loans { loan-id: loan-id } (merge loan { status: "liquidated" }))
      ;; Remove from user's active loans
      (remove-loan-from-user (get borrower loan) loan-id)
      ;; Update platform metrics
      (var-set total-btc-locked
        (- (var-get total-btc-locked) (get collateral-amount loan))
      )
      (ok true)
    )
    ERR-LOAN-NOT-FOUND
  )
)

;; ADMINISTRATIVE FUNCTIONS

;; Initialize the lending protocol
(define-public (initialize-platform)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get platform-initialized)) ERR-ALREADY-INITIALIZED)
    ;; Set initial price feeds
    (map-set asset-prices { asset: "BTC" } {
      price: u4000000000000,
      last-updated: stacks-block-height,
      oracle: tx-sender,
    })
    (map-set asset-prices { asset: "STX" } {
      price: u200000000,
      last-updated: stacks-block-height,
      oracle: tx-sender,
    })
    (var-set platform-initialized true)
    (ok "BitLend Protocol Initialized Successfully")
  )
)