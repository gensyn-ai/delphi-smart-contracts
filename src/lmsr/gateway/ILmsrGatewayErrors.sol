// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";

/// @title ILmsrGatewayErrors
/// @notice Errors thrown by the LmsrGateway contract.
interface ILmsrGatewayErrors is ILmsrMathErrors {
    // ===== CONSTRUCTOR =====

    /// @notice Thrown when the token address is the zero address.
    error TokenIsZeroAddress();

    /// @notice Thrown when the token address has no code.
    /// @param token The provided token address.
    error TokenIsNotAContract(address token);

    /// @notice Thrown when the token has fewer than 6 decimals.
    /// @param decimals The token's decimals.
    error TokenDecimalsAreTooLow(uint8 decimals);

    /// @notice Thrown when the token has more than 18 decimals.
    /// @param decimals The token's decimals.
    error TokenDecimalsAreTooHigh(uint8 decimals);

    // ===== INITIALIZE =====

    /// @notice Thrown when someone other than the deployer tries to initialize the gateway.
    /// @param initializer The caller.
    /// @param deployer The address that deployed the gateway.
    error InitializerNotDeployer(address initializer, address deployer);

    /// @notice Thrown when the Delphi factory address is the zero address.
    error DelphiFactoryIsZeroAddress();

    /// @notice Thrown when the Delphi factory address has no code.
    /// @param delphiFactory The provided factory address.
    error DelphiFactoryIsNotContract(address delphiFactory);

    // ===== BUY EXACT OUT WITH PERMIT =====

    /// @notice Thrown when the permit fails and the existing allowance is insufficient.
    /// @param allowance The current allowance from the buyer to the market proxy.
    /// @param maxTokensIn The required allowance.
    error AllowanceTooLow(uint256 allowance, uint256 maxTokensIn);

    // ===== BUY EXACT OUT =====

    /// @notice Thrown when the quoted tokens in exceed the caller's maximum (slippage protection).
    /// @param tokensIn The quoted tokens in.
    /// @param maxTokensIn The caller-provided maximum.
    error TokensInExceedMaxTokensIn(uint256 tokensIn, uint256 maxTokensIn);

    // ===== SELL EXACT IN =====

    /// @notice Thrown when the quoted tokens out are below the caller's minimum (slippage protection).
    /// @param tokensOut The quoted tokens out.
    /// @param minTokensOut The caller-provided minimum.
    error TokensOutBelowMinTokensOut(uint256 tokensOut, uint256 minTokensOut);

    // ===== SET ORACLE RELAYER =====

    /// @notice Thrown when the oracle relayer address is the zero address.
    error OracleRelayerIsZeroAddress();

    /// @notice Thrown when the oracle relayer address has no code.
    /// @param oracleRelayer The provided oracle relayer address.
    error OracleRelayerIsNotAContract(address oracleRelayer);

    // ===== RESOLVE MARKET =====

    /// @notice Thrown when resolution is requested before an oracle relayer is wired.
    error OracleRelayerNotSet();

    /// @notice Thrown when resolution is requested for a market whose settlement is already locked.
    /// @param marketProxy The market proxy address.
    error SettlementAlreadyLocked(address marketProxy);

    // ===== SETTLE/FAIL MARKET =====

    /// @notice Thrown when settling/failing a market without a prior gateway-issued resolution request.
    error SettlementNotLocked();

    // ===== QUOTE BUY EXACT OUT =====

    /// @notice Thrown when the requested shares out are below the minimum trade size.
    /// @param sharesOut The requested shares out.
    /// @param minDelta The minimum shares delta (MIN_SHARES_DELTA).
    error SharesOutBelowMinDelta(uint256 sharesOut, uint256 minDelta);

    /// @notice Thrown when the quoted tokens in are below the minimum token trade size.
    /// @param tokensIn The quoted tokens in.
    /// @param minTokensIn The minimum tokens delta (MIN_TOKENS_DELTA).
    error TokensInBelowMinTokensDelta(uint256 tokensIn, uint256 minTokensIn);

    // ===== QUOTE SELL EXACT IN =====

    /// @notice Thrown when the requested shares in are below the minimum trade size.
    /// @param sharesIn The requested shares in.
    /// @param minDelta The minimum shares delta (MIN_SHARES_DELTA).
    error SharesInBelowMinDelta(uint256 sharesIn, uint256 minDelta);

    /// @notice Thrown when a sell would leave the outcome supply between zero and the minimum trade size.
    /// @param newSupply The outcome supply after the sell.
    /// @param minDelta The minimum shares delta (MIN_SHARES_DELTA).
    error OutcomeNewSupplyBelowMinDelta(uint256 newSupply, uint256 minDelta);

    /// @notice Thrown when the quoted tokens out are below the minimum token trade size.
    /// @param tokensOut The quoted tokens out.
    /// @param minTokensOut The minimum tokens delta (MIN_TOKENS_DELTA).
    error TokensOutBelowMinTokensDelta(uint256 tokensOut, uint256 minTokensOut);

    // ===== IF DEPLOYED BY FACTORY =====

    /// @notice Thrown when the gateway is used before initialize() has been called.
    error GatewayNotInitialized();

    /// @notice Thrown when the target market proxy was not deployed by the registered factory.
    /// @param marketProxy The provided market proxy address.
    error MarketProxyNotDeployedByFactory(address marketProxy);

    // ===== IF OPEN =====

    /// @notice Thrown when the market is not in the OPEN status.
    error MarketNotOpen();

    // ===== ONLY ORACLE RELAYER =====

    /// @notice Thrown when the caller is not the registered oracle relayer.
    /// @param caller The caller.
    error CallerIsNotOracleRelayer(address caller);
}
