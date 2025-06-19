# BitLend Protocol

[![Stacks](https://img.shields.io/badge/built%20on-Stacks-orange.svg)](https://stacks.co)
[![Bitcoin](https://img.shields.io/badge/collateral-Bitcoin-yellow.svg)](https://bitcoin.org)

## Overview

BitLend is a decentralized, trustless lending protocol built on the Stacks blockchain that enables users to borrow against Bitcoin (BTC) and STX collateral. The protocol provides instant liquidity while maintaining the security and decentralization principles of the Bitcoin ecosystem.

### Key Features

- **Multi-Asset Collateral**: Support for BTC and STX as collateral
- **Dynamic Risk Management**: Configurable collateral ratios and liquidation thresholds
- **Real-Time Interest Calculation**: Block-based compound interest with precise calculations
- **Automated Liquidation**: Protection system for both lenders and borrowers
- **Oracle Integration**: Real-time price feeds for accurate asset valuation
- **Comprehensive Analytics**: Full portfolio tracking and platform metrics

## System Architecture

### High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Users       │    │   Price Oracle  │    │  Liquidation    │
│                 │    │                 │    │    Engine       │
│ • Borrowers     │    │ • BTC/USD       │    │                 │
│ • Liquidators   │    │ • STX/USD       │    │ • Health Check  │
│ • Admins        │    │ • Real-time     │    │ • Auto Execute  │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────▼─────────────┐
                    │                           │
                    │     BitLend Protocol      │
                    │      Smart Contract       │
                    │                           │
                    │ • Loan Management         │
                    │ • Collateral Handling     │
                    │ • Interest Calculation    │
                    │ • Risk Assessment         │
                    │ • Portfolio Tracking      │
                    │                           │
                    └───────────────────────────┘
```

### Contract Architecture

#### Core Components

1. **Loan Engine**
   - Loan creation and management
   - Collateral ratio calculations
   - Interest computation with compound logic
   - Repayment processing

2. **Risk Management System**
   - Minimum collateral ratio enforcement (150% default)
   - Liquidation threshold monitoring (120% default)
   - Dynamic risk parameter updates
   - Health factor calculations

3. **Oracle Integration**
   - Real-time price feed management
   - Authorized oracle system
   - Price validation and integrity checks
   - Multi-asset price support

4. **Liquidation Engine**
   - Automated position monitoring
   - Liquidation eligibility detection
   - Liquidation execution
   - Collateral redistribution

5. **Analytics & Reporting**
   - Total Value Locked (TVL) tracking
   - Protocol revenue monitoring
   - User portfolio management
   - Platform metrics aggregation

## Data Flow

### Loan Creation Flow

```
1. User Request
   ├── Collateral Asset Selection (BTC/STX)
   ├── Collateral Amount Input
   └── Loan Amount Request

2. Validation Layer
   ├── Platform Status Check
   ├── Asset Support Verification
   ├── Amount Validation
   └── Collateral Ratio Check

3. Price Oracle Query
   ├── Current Asset Price Fetch
   ├── Price Validity Check
   └── Collateral Value Calculation

4. Risk Assessment
   ├── Collateral Ratio Calculation
   ├── Minimum Ratio Verification
   └── Health Factor Determination

5. Loan Creation
   ├── Unique Loan ID Generation
   ├── Loan Record Storage
   ├── User Portfolio Update
   └── Platform Metrics Update

6. Fund Distribution
   ├── Platform Fee Calculation
   ├── Net Amount Determination
   └── Loan Disbursement
```

### Liquidation Flow

```
1. Health Monitoring
   ├── Continuous Position Tracking
   ├── Price Feed Updates
   └── Collateral Ratio Recalculation

2. Liquidation Trigger
   ├── Threshold Breach Detection (<120%)
   ├── Liquidation Eligibility Check
   └── Automated Alert System

3. Liquidation Execution
   ├── Position Status Update
   ├── Collateral Seizure
   ├── User Portfolio Cleanup
   └── Platform Metrics Update
```

## Core Functions

### Administrative Functions

- `initialize-platform()`: Initialize the protocol with default settings
- `set-risk-parameters()`: Update collateral ratios and liquidation thresholds
- `update-asset-price()`: Oracle function for price feed updates
- `toggle-platform-pause()`: Emergency pause mechanism

### Core Lending Functions

- `create-loan()`: Deposit collateral and create a new loan
- `repay-loan()`: Repay loan with accumulated interest
- `liquidate-loan()`: Liquidate undercollateralized positions

### Query Functions

- `get-loan-info()`: Retrieve comprehensive loan details
- `get-user-portfolio()`: Get user's complete lending portfolio
- `get-platform-analytics()`: Current platform statistics
- `get-risk-parameters()`: Current risk management settings
- `get-asset-price()`: Current asset price information

## Risk Management

### Collateral Requirements

- **Minimum Collateral Ratio**: 150% (configurable)
- **Liquidation Threshold**: 120% (configurable)
- **Maximum Loans per User**: 10 loans
- **Supported Assets**: BTC, STX

### Interest Rate Model

- **Base Interest Rate**: 5% annually (500 basis points)
- **Compound Interest**: Block-based calculation
- **Interest Frequency**: Calculated per block (~10 minutes)

### Platform Fees

- **Origination Fee**: 1% of loan amount (100 basis points)
- **Fee Structure**: Deducted from loan disbursement
- **Revenue Tracking**: All fees tracked in protocol revenue

## Security Features

### Access Control

- **Owner-only Functions**: Risk parameter updates, platform initialization
- **Authorized Oracles**: Whitelisted price feed providers
- **User Authorization**: Loan access restricted to loan owners

### Validation & Safety

- **Arithmetic Overflow Protection**: Safe math operations
- **Input Validation**: Comprehensive parameter checking
- **Price Feed Validation**: Price bounds and freshness checks
- **Emergency Controls**: Platform pause functionality

### Liquidation Protection

- **Automated Monitoring**: Continuous health factor tracking
- **Fair Liquidation**: Market-based liquidation execution
- **Borrower Protection**: Advance warning through health factors

## Platform Analytics

The protocol tracks comprehensive metrics including:

- **Total Value Locked (TVL)**: Combined BTC and STX collateral value
- **Total Loans Issued**: Cumulative loan count
- **Protocol Revenue**: Fees and interest collected
- **Asset Distribution**: BTC vs STX collateral breakdown
- **Active Loan Statistics**: Current borrowing activity

## Getting Started

### Prerequisites

- Stacks wallet (Hiro Wallet, Xverse, etc.)
- BTC or STX for collateral
- Understanding of DeFi lending risks

### Basic Usage

1. **Connect Wallet**: Connect your Stacks-compatible wallet
2. **Initialize Position**: Call `create-loan()` with desired collateral and loan amount
3. **Monitor Health**: Track your collateral ratio through `get-loan-info()`
4. **Repay Loan**: Use `repay-loan()` to close position and retrieve collateral

## Risk Disclosure

- **Smart Contract Risk**: Code audits recommended before mainnet deployment
- **Price Risk**: Asset price volatility may trigger liquidations
- **Liquidation Risk**: Positions below 120% collateral ratio face liquidation
- **Oracle Risk**: Price feed accuracy dependencies

## Development Status

**⚠️ This contract is for educational and development purposes. Conduct thorough testing and audits before any production deployment.**

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

For questions and support:

- Create an issue in this repository
- Join our community discussions
- Review the documentation wiki
