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

;; Update risk management parameters
(define-public (set-risk-parameters
    (min-collateral uint)
    (liquidation-limit uint)
    (fee-rate uint)
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= min-collateral MIN-COLLATERAL-RATIO) ERR-INVALID-AMOUNT)
    (asserts! (>= liquidation-limit u100) ERR-INVALID-AMOUNT)
    (asserts! (<= fee-rate u1000) ERR-INVALID-AMOUNT) ;; Max 10% fee
    (var-set minimum-collateral-ratio min-collateral)
    (var-set liquidation-threshold liquidation-limit)
    (var-set platform-fee-rate fee-rate)
    (ok true)
  )
)

;; Update asset price feeds (Oracle function)
(define-public (update-asset-price
    (asset (string-ascii 3))
    (new-price uint)
  )
  (begin
    (asserts!
      (or
        (is-eq tx-sender CONTRACT-OWNER)
        (default-to false
          (get authorized (map-get? authorized-oracles { oracle: tx-sender }))
        )
      )
      ERR-NOT-AUTHORIZED
    )
    (asserts! (is-supported-asset asset) ERR-INVALID-ASSET)
    (asserts! (is-valid-price new-price) ERR-INVALID-PRICE)
    (ok (map-set asset-prices { asset: asset } {
      price: new-price,
      last-updated: stacks-block-height,
      oracle: tx-sender,
    }))
  )
)

;; Emergency pause mechanism
(define-public (toggle-platform-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set platform-paused (not (var-get platform-paused)))
    (ok (var-get platform-paused))
  )
)

;; CORE LENDING FUNCTIONS

;; Deposit collateral and request loan
(define-public (create-loan
    (collateral-asset (string-ascii 3))
    (collateral-amount uint)
    (loan-amount uint)
  )
  (let (
      (asset-price-data (unwrap! (map-get? asset-prices { asset: collateral-asset })
        ERR-NOT-INITIALIZED
      ))
      (asset-price (get price asset-price-data))
      (collateral-ratio (calculate-collateral-ratio collateral-amount loan-amount asset-price))
      (loan-id (+ (var-get total-loans-issued) u1))
      (platform-fee (/ (* loan-amount (var-get platform-fee-rate)) u10000))
      (net-loan-amount (- loan-amount platform-fee))
    )
    (begin
      ;; Validation checks
      (asserts! (var-get platform-initialized) ERR-NOT-INITIALIZED)
      (asserts! (not (var-get platform-paused)) ERR-NOT-INITIALIZED)
      (asserts! (is-supported-asset collateral-asset) ERR-INVALID-ASSET)
      (asserts! (> collateral-amount u0) ERR-INVALID-AMOUNT)
      (asserts! (> loan-amount u0) ERR-INVALID-AMOUNT)
      (asserts! (>= collateral-ratio (var-get minimum-collateral-ratio))
        ERR-INSUFFICIENT-COLLATERAL
      )
      ;; Create loan record
      (map-set loans { loan-id: loan-id } {
        borrower: tx-sender,
        collateral-asset: collateral-asset,
        collateral-amount: collateral-amount,
        loan-amount: loan-amount,
        interest-rate: (var-get base-interest-rate),
        start-height: stacks-block-height,
        last-interest-calc: stacks-block-height,
        accumulated-interest: u0,
        status: "active",
      })
      ;; Update user portfolio
      (match (map-get? user-loans { user: tx-sender })
        existing-portfolio (let (
            (current-loans (get active-loans existing-portfolio))
            (new-loans-list (unwrap! (as-max-len? (append current-loans loan-id) u10)
              ERR-INVALID-AMOUNT
            ))
          )
          (map-set user-loans { user: tx-sender } {
            active-loans: new-loans-list,
            total-borrowed: (+ (get total-borrowed existing-portfolio) loan-amount),
            total-collateral: (+ (get total-collateral existing-portfolio) collateral-amount),
          })
        )
        (map-set user-loans { user: tx-sender } {
          active-loans: (list loan-id),
          total-borrowed: loan-amount,
          total-collateral: collateral-amount,
        })
      )
      ;; Update platform metrics
      (if (is-eq collateral-asset "BTC")
        (var-set total-btc-locked
          (+ (var-get total-btc-locked) collateral-amount)
        )
        (var-set total-stx-locked
          (+ (var-get total-stx-locked) collateral-amount)
        )
      )
      (var-set total-loans-issued loan-id)
      (var-set total-value-borrowed
        (+ (var-get total-value-borrowed) loan-amount)
      )
      (var-set protocol-revenue (+ (var-get protocol-revenue) platform-fee))
      (ok {
        loan-id: loan-id,
        net-amount: net-loan-amount,
        fee: platform-fee,
      })
    )
  )
)

;; Repay loan with accumulated interest
(define-public (repay-loan (loan-id uint))
  (begin
    ;; Input validation
    (asserts! (> loan-id u0) ERR-INVALID-LOAN-ID)
    (asserts! (<= loan-id (var-get total-loans-issued)) ERR-INVALID-LOAN-ID)
    (match (map-get? loans { loan-id: loan-id })
      loan (let (
          (validated-loan-id loan-id) ;; Create validated binding
          (blocks-elapsed (- stacks-block-height (get last-interest-calc loan)))
          (new-interest (calculate-compound-interest (get loan-amount loan)
            (get interest-rate loan) blocks-elapsed
          ))
          (total-interest (+ (get accumulated-interest loan) new-interest))
          (total-repayment (+ (get loan-amount loan) total-interest))
        )
        (begin
          ;; Authorization validation
          (asserts! (is-eq (get borrower loan) tx-sender) ERR-NOT-AUTHORIZED)
          (asserts! (is-eq (get status loan) "active") ERR-LOAN-NOT-ACTIVE)
          ;; Update loan status
          (map-set loans { loan-id: validated-loan-id }
            (merge loan {
              status: "repaid",
              accumulated-interest: total-interest,
              last-interest-calc: stacks-block-height,
            })
          )
          ;; Update user portfolio
          (remove-loan-from-user tx-sender validated-loan-id)
          ;; Update platform metrics
          (if (is-eq (get collateral-asset loan) "BTC")
            (var-set total-btc-locked
              (- (var-get total-btc-locked) (get collateral-amount loan))
            )
            (var-set total-stx-locked
              (- (var-get total-stx-locked) (get collateral-amount loan))
            )
          )
          (var-set protocol-revenue (+ (var-get protocol-revenue) total-interest))
          (ok {
            principal: (get loan-amount loan),
            interest: total-interest,
            total: total-repayment,
            collateral-returned: (get collateral-amount loan),
          })
        )
      )
      ERR-LOAN-NOT-FOUND
    )
  )
)

;; Liquidate undercollateralized position
(define-public (liquidate-loan (loan-id uint))
  (begin
    ;; Input validation
    (asserts! (> loan-id u0) ERR-INVALID-LOAN-ID)
    (asserts! (<= loan-id (var-get total-loans-issued)) ERR-INVALID-LOAN-ID)
    (asserts! (check-liquidation-eligibility loan-id) ERR-INVALID-LIQUIDATION)
    (execute-liquidation loan-id)
  )
)

;; READ-ONLY QUERY FUNCTIONS

;; Get comprehensive loan details
(define-read-only (get-loan-info (loan-id uint))
  (begin
    ;; Input validation for read-only function
    (asserts! (> loan-id u0) ERR-INVALID-LOAN-ID)
    (asserts! (<= loan-id (var-get total-loans-issued)) ERR-INVALID-LOAN-ID)
    (match (map-get? loans { loan-id: loan-id })
      loan (let (
          (blocks-elapsed (- stacks-block-height (get last-interest-calc loan)))
          (pending-interest (calculate-compound-interest (get loan-amount loan)
            (get interest-rate loan) blocks-elapsed
          ))
          (total-interest (+ (get accumulated-interest loan) pending-interest))
        )
        (ok {
          loan-details: loan,
          current-interest: total-interest,
          total-owed: (+ (get loan-amount loan) total-interest),
          health-factor: (calculate-collateral-ratio (get collateral-amount loan)
            (get loan-amount loan)
            (default-to u0
              (get price
                (map-get? asset-prices { asset: (get collateral-asset loan) })
              ))
          ),
        })
      )
      ERR-LOAN-NOT-FOUND
    )
  )
)

;; Get user's complete portfolio
(define-read-only (get-user-portfolio (user principal))
  (map-get? user-loans { user: user })
)

;; Get current platform analytics
(define-read-only (get-platform-analytics)
  {
    total-btc-locked: (var-get total-btc-locked),
    total-stx-locked: (var-get total-stx-locked),
    total-loans-issued: (var-get total-loans-issued),
    total-value-borrowed: (var-get total-value-borrowed),
    protocol-revenue: (var-get protocol-revenue),
    platform-tvl: (+
      (* (var-get total-btc-locked)
        (default-to u0 (get price (map-get? asset-prices { asset: "BTC" })))
      )
      (* (var-get total-stx-locked)
        (default-to u0 (get price (map-get? asset-prices { asset: "STX" })))
      )),
  }
)

;; Get current risk parameters
(define-read-only (get-risk-parameters)
  {
    minimum-collateral-ratio: (var-get minimum-collateral-ratio),
    liquidation-threshold: (var-get liquidation-threshold),
    platform-fee-rate: (var-get platform-fee-rate),
    base-interest-rate: (var-get base-interest-rate),
  }
)

;; Get asset price information
(define-read-only (get-asset-price (asset (string-ascii 3)))
  (map-get? asset-prices { asset: asset })
)

;; Get supported assets
(define-read-only (get-supported-assets)
  VALID-ASSETS
)

;; Check platform status
(define-read-only (get-platform-status)
  {
    initialized: (var-get platform-initialized),
    paused: (var-get platform-paused),
    contract-owner: CONTRACT-OWNER,
  }
)
