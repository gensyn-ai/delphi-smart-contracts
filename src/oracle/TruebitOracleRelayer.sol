// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IBaseTBContract} from "src/oracle/truebit/interfaces/IBaseTBContract.sol";
import {IWatchTower} from "src/oracle/truebit/interfaces/IWatchTower.sol";
import {DOTypes} from "src/oracle/truebit/abstract/Types.sol";
import {IOracle} from "src/IOracle.sol";
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

/// @title TruebitOracleRelayer
/// @notice UUPS-upgradeable oracle relayer that integrates the Delphi gateway with the Truebit WatchTower.
/// @dev Implements IOracle and IBaseTBContract directly (does NOT inherit Truebit's BaseTBContract — see
///      below). Deployed behind an ERC1967 proxy; upgrade the implementation to swap task configuration or
///      oracle logic without redeploying the proxy or changing the gateway's oracleRelayer address.
///
///      Truebit integration shape (per Truebit team guidance): we do not inherit the vendored
///      `BaseTBContract`. Instead we implement `IBaseTBContract` and call `watchTower.requestExecution`
///      ourselves with `codeHash = bytes32(0)`. For registered tasks (FUNCTION / API — our use case) the
///      WatchTower ignores `codeHash` entirely (it is not validated on- or off-chain, only emitted in the
///      `TaskRequested` event), so `bytes32(0)` is safe and intended. This keeps the relayer fully owning
///      its storage layout (ERC-7201 namespaced) with no foreign sequential slots from a base contract.
contract TruebitOracleRelayer is IBaseTBContract, UUPSUpgradeable, Ownable2StepUpgradeable, IOracle {
    // ========== CONSTANTS ==========

    /// @notice Truebit method signature for API task execution.
    string public constant METHOD_SIGNATURE = "request(namespace,taskname,method,path,executionTimeout,async,body)";

    /// @notice Truebit task parameters — fixed per relayer version. Changing any requires a new
    ///         implementation + UUPS upgrade (same mechanism as any other logic change).
    string public constant NAMESPACE = "gensyn";
    string public constant TASKNAME = "workflow_entry";
    string public constant METHOD = "POST";
    string public constant PATH = "/webhook/settlement";

    // ========== IMMUTABLES ==========

    /// @notice The Truebit WatchTower this relayer submits execution requests to.
    /// @dev Set in the constructor, so it lives in the implementation bytecode (not proxy storage) and reads
    ///      correctly through the proxy. Changing the WatchTower requires a new implementation + UUPS upgrade.
    IWatchTower public immutable WATCHTOWER;

    /// @notice The Delphi gateway — the only authorized caller of resolveMarket, and the target of
    ///         failMarket/settleMarket callbacks.
    ILmsrGateway public immutable GATEWAY;

    /// @notice Truebit task execution timeout in seconds.
    uint256 public immutable EXECUTION_TIMEOUT;

    /// @notice Whether the Truebit task executes asynchronously.
    bool public immutable ASYNC;

    // ========== ERC-7201 STORAGE ==========

    /// @custom:storage-location erc7201:TruebitOracleRelayer
    struct TruebitOracleRelayerStorage {
        /// @dev Address that receives the oracle fee on successful market settlement (e.g. Truebit treasury).
        address oracleFeeRecipient;
        /// @dev Tracks in-flight WatchTower requests. Maps wtExecutionId => marketProxy.
        mapping(uint256 wtExecutionId => address marketProxy) pendingRequests;
    }

    // ERC7201(TruebitOracleRelayer)
    bytes32 private constant _TRUEBIT_ORACLE_RELAYER_STORAGE_SLOT =
        0x7601f7d73f2a6cd2a45335c3aee62fe881497ea5d524db3da0803692394acc00;

    function _getTruebitOracleRelayerStorage() private pure returns (TruebitOracleRelayerStorage storage $) {
        assembly ("memory-safe") {
            $.slot := _TRUEBIT_ORACLE_RELAYER_STORAGE_SLOT
        }
    }

    // ========== ERRORS ==========

    /// @notice Thrown when the caller is not the gateway.
    /// @param caller The caller.
    error CallerIsNotGateway(address caller);
    /// @notice Thrown when a callback references an execution id with no pending request.
    /// @param wtExecutionId The unknown WatchTower execution id.
    error UnknownExecutionId(uint256 wtExecutionId);
    /// @notice Thrown when the caller is not the WatchTower.
    /// @param sender The caller.
    error NotWatchTower(address sender);
    /// @notice Thrown when the oracle fee recipient is the zero address.
    error OracleFeeRecipientIsZeroAddress();
    /// @notice Thrown when the gateway address is the zero address.
    error GatewayIsZeroAddress();
    /// @notice Thrown when the WatchTower address is the zero address.
    error ZeroWatchTowerAddress();
    /// @notice Thrown when the execution timeout is zero.
    error ZeroExecutionTimeout();
    /// @notice Thrown when the WatchTower returns an execution id that already has a pending request.
    /// @param wtExecutionId The duplicate WatchTower execution id.
    error DuplicateExecutionId(uint256 wtExecutionId);

    // ========== ENUMS ==========

    /// @notice Why a market resolution was failed instead of settled.
    enum FailureReason {
        EXECUTION_FAILED, // WatchTower returned non-SUCCESS status
        MALFORMED_RESULT, // resultData length != 32
        INVALID_OUTCOME // decoded outcomeIdx out of bounds
    }

    // ========== EVENTS ==========

    /// @notice Emitted when a WatchTower execution request is submitted for a market.
    /// @param marketProxy The market proxy being resolved.
    /// @param wtExecutionId The WatchTower execution id tracking the request.
    event ResolutionRequested(address indexed marketProxy, uint256 indexed wtExecutionId);

    /// @notice Emitted when a callback fails a market instead of settling it.
    /// @param marketProxy The market proxy that was failed.
    /// @param wtExecutionId The WatchTower execution id of the callback.
    /// @param reason Why the resolution was failed.
    /// @param executionStatus The raw WatchTower status — only meaningful when reason is EXECUTION_FAILED, zero otherwise.
    event ResolutionFailed(
        address indexed marketProxy, uint256 indexed wtExecutionId, FailureReason reason, uint8 executionStatus
    );

    /// @notice Emitted when the oracle fee recipient is updated.
    /// @param previousRecipient The previous oracle fee recipient.
    /// @param newRecipient The new oracle fee recipient.
    event OracleFeeRecipientSet(address indexed previousRecipient, address indexed newRecipient);
    /// @notice Surfaces the full WatchTower callback payload — notably `transcripts` — for off-chain
    ///         consumers (the backend). Emitted once per known-id callback regardless of outcome, before
    ///         the gateway settle/fail interaction (so it is rolled back if that interaction reverts).
    /// @param resultData The raw result bytes returned by the WatchTower.
    /// @param transcripts The WatchTower execution transcripts.
    event CallbackReceived(
        address indexed marketProxy, uint256 indexed wtExecutionId, uint8 status, bytes resultData, string[] transcripts
    );

    // ========== MODIFIERS ==========

    modifier onlyGateway() {
        _requireGateway();
        _;
    }

    /// @dev Restricts the caller to the WatchTower address. NOTE: this grants no trust — the WatchTower is
    ///      treated as potentially malicious. Every guard in callbackTask is a security check, not defensive
    ///      programming.
    modifier onlyWatchTower() {
        _requireWatchTower();
        _;
    }

    // ========== CONSTRUCTOR ==========

    /// @dev Sets watchTower, GATEWAY, EXECUTION_TIMEOUT, and ASYNC as immutables in implementation
    ///      bytecode. Blocks re-initialization.
    constructor(address watchTower_, ILmsrGateway gateway_, uint256 executionTimeout_, bool async_) {
        if (watchTower_ == address(0)) revert ZeroWatchTowerAddress();
        if (address(gateway_) == address(0)) revert GatewayIsZeroAddress();
        if (executionTimeout_ == 0) revert ZeroExecutionTimeout();
        WATCHTOWER = IWatchTower(watchTower_);
        GATEWAY = gateway_;
        EXECUTION_TIMEOUT = executionTimeout_;
        ASYNC = async_;
        _disableInitializers();
    }

    // ========== INITIALIZER ==========

    /// @notice Initialization parameters for the relayer proxy.
    struct InitParams {
        /// @dev The relayer owner (can set the oracle fee recipient and authorize UUPS upgrades).
        address owner;
        /// @dev The address that receives the oracle fee on successful settlement.
        address oracleFeeRecipient;
    }

    /// @notice Initializes the relayer proxy. Can only be called once.
    /// @param p The initialization parameters (owner, oracle fee recipient).
    function initialize(InitParams calldata p) external initializer {
        if (p.oracleFeeRecipient == address(0)) revert OracleFeeRecipientIsZeroAddress();
        __Ownable_init(p.owner);
        __Ownable2Step_init();
        _getTruebitOracleRelayerStorage().oracleFeeRecipient = p.oracleFeeRecipient;
    }

    // ========== IORACLE ==========

    /// @inheritdoc IOracle
    /// @dev Only callable by the registered gateway. The gateway guarantees settlementLocked
    ///      was set before this call, so no double-resolution is possible.
    function resolveMarket(address marketProxy) external override onlyGateway {
        ILmsrMarket market = ILmsrMarket(marketProxy);
        string memory body = string.concat(
            '{"metadata_path": "',
            market.getMarketMetadata().uri,
            '", "created_at": ',
            Strings.toString(market.createdAt()),
            ', "resolves_at": ',
            Strings.toString(market.getMarket().config.tradingDeadline),
            "}"
        );

        bytes memory payload = abi.encode(NAMESPACE, TASKNAME, METHOD, PATH, EXECUTION_TIMEOUT, ASYNC, body);

        // Direct WatchTower request. codeHash = bytes32(0) is intentional: confirmed by the Truebit team
        // that for registered tasks (FUNCTION / API — our case) the codeHash is ignored entirely (not
        // validated on- or off-chain, only emitted in the TaskRequested event).
        uint256 wtExecutionId =
            WATCHTOWER.requestExecution(METHOD_SIGNATURE, payload, bytes32(0), DOTypes.ExecutionType.API);

        // CEI note: the pendingRequests write happens AFTER the external requestExecution call
        // because wtExecutionId is its return value. This is not a re-entrancy risk: resolveMarket
        // is onlyGateway, and the gateway's settlementLocked flag blocks a second resolution of the
        // same market, so the WatchTower cannot re-enter this path.
        //
        // The WatchTower-supplied id is untrusted (same threat model as callbackTask). An honest
        // WatchTower uses unique, monotonically-increasing ids; a malicious one could return a
        // duplicate to overwrite an existing entry and orphan the earlier market. Reject collisions
        // explicitly rather than trusting uniqueness.
        TruebitOracleRelayerStorage storage $ = _getTruebitOracleRelayerStorage();
        if ($.pendingRequests[wtExecutionId] != address(0)) revert DuplicateExecutionId(wtExecutionId);
        $.pendingRequests[wtExecutionId] = marketProxy;
        emit ResolutionRequested(marketProxy, wtExecutionId);
    }

    /// @inheritdoc IBaseTBContract
    /// @dev WatchTower callback. Parses outcomeIdx from resultData, bounds-checks it,
    ///      and settles the market. On any failure the market is failed — it can no longer settle.
    ///
    /// SECURITY: The WatchTower must be treated as a potentially malicious contract.
    /// `onlyWatchTower` restricts the caller to the WatchTower address but provides no
    /// protection if the WatchTower itself is compromised. Every check below is a security
    /// guard against a malicious WatchTower:
    ///   - `pendingRequests` lookup: prevents settling a market that was never requested
    ///   - `delete` before external call: prevents replay of the same callback (CEI pattern)
    ///   - `status` check: prevents falsely claiming success on a failed task
    ///   - `outcomeIdx` bounds check: prevents an out-of-bounds outcome breaking the market
    function callbackTask(
        bytes calldata resultData,
        string[] memory transcripts,
        uint256 wtExecutionId,
        uint8 status,
        string memory /* callbackMessageDetails */
    ) external override onlyWatchTower {
        TruebitOracleRelayerStorage storage $ = _getTruebitOracleRelayerStorage();

        // Guard: reject callbacks for requests we never made.
        // Revert (not return) so the WatchTower's try/catch emits CallbackFailed
        // rather than RequestFulfilled — unknown IDs are not successful callbacks.
        address marketProxy = $.pendingRequests[wtExecutionId];
        if (marketProxy == address(0)) {
            revert UnknownExecutionId(wtExecutionId);
        }

        // Effects: delete before any external call to prevent replay.
        // NOTE: if the downstream gateway call reverts (e.g. market already EXPIRED when
        // callback arrives), this delete is rolled back and the entry stays in pendingRequests.
        // This is harmless on two independent layers:
        //   1. Honest WatchTower: marks the request as fulfilled before calling us
        //      (AlreadyFulfilled guard), so it will never replay this callback.
        //   2. Malicious WatchTower: even if it replays, market.failMarket() and
        //      market.settleMarket() both carry ifStatus(AWAITING_SETTLEMENT) — they
        //      always revert on an EXPIRED/FAILED market, making any replay a no-op.
        delete $.pendingRequests[wtExecutionId];

        // Effects: surface the full callback payload (notably the transcripts) for off-chain consumers,
        // before any gateway interaction. Emitted once per known-id callback regardless of outcome;
        // rolled back together with the delete above if a downstream settle/fail reverts.
        emit CallbackReceived(marketProxy, wtExecutionId, status, resultData, transcripts);

        // Guard: reject non-SUCCESS callbacks. Compare as uint8 before casting to avoid
        // runtime revert on out-of-range values (Solidity 0.8 enum casts are checked).
        // A malicious WatchTower passing an out-of-range status would otherwise revert
        // and roll back the CEI delete above, re-opening the replay window.
        if (status != uint8(DOTypes.ExecutionStatus.SUCCESS)) {
            GATEWAY.failMarket(marketProxy);
            emit ResolutionFailed(marketProxy, wtExecutionId, FailureReason.EXECUTION_FAILED, status);
            return;
        }

        // Guard: reject malformed result (ABI-encoded uint256 is exactly 32 bytes)
        if (resultData.length != 32) {
            GATEWAY.failMarket(marketProxy);
            emit ResolutionFailed(marketProxy, wtExecutionId, FailureReason.MALFORMED_RESULT, status);
            return;
        }

        uint256 outcomeIdx = _parseOutcomeIdx(resultData);

        // Guard: reject out-of-bounds outcome index
        if (!ILmsrMarket(marketProxy).isValidOutcomeIdx(outcomeIdx)) {
            GATEWAY.failMarket(marketProxy);
            emit ResolutionFailed(marketProxy, wtExecutionId, FailureReason.INVALID_OUTCOME, status);
            return;
        }

        // Interaction: settle the market and transfer oracle fee to treasury atomically
        GATEWAY.settleMarket(marketProxy, outcomeIdx, $.oracleFeeRecipient);
    }

    /// @inheritdoc IBaseTBContract
    /// @dev Unused for registered (FUNCTION / API) tasks — no source code lives on-chain. Returns empty.
    function getTaskSource() external pure returns (string memory) {
        return "";
    }

    // ========== OWNER ==========

    /// @notice Updates the oracle fee recipient address. Only callable by the owner.
    /// @param recipient The new oracle fee recipient address.
    function setOracleFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert OracleFeeRecipientIsZeroAddress();
        TruebitOracleRelayerStorage storage $ = _getTruebitOracleRelayerStorage();
        emit OracleFeeRecipientSet($.oracleFeeRecipient, recipient);
        $.oracleFeeRecipient = recipient;
    }

    // ========== GETTERS ==========

    // watchTower, GATEWAY, EXECUTION_TIMEOUT, ASYNC — auto-generated by public immutable declarations above.
    // METHOD_SIGNATURE, NAMESPACE, TASKNAME, METHOD, PATH — auto-generated by public constant declarations above.

    /// @return The address that receives the oracle fee on successful market settlement.
    function oracleFeeRecipient() external view returns (address) {
        return _getTruebitOracleRelayerStorage().oracleFeeRecipient;
    }

    /// @param wtExecutionId The WatchTower execution id to look up.
    /// @return The market proxy awaiting a callback for this execution id (zero address if none).
    function pendingRequests(uint256 wtExecutionId) external view returns (address) {
        return _getTruebitOracleRelayerStorage().pendingRequests[wtExecutionId];
    }

    // ========== INTERNAL ==========

    /// @dev Decodes the winning outcome index from the WatchTower result bytes (ABI-encoded uint256).
    function _parseOutcomeIdx(bytes calldata resultData) internal pure returns (uint256) {
        return abi.decode(resultData, (uint256));
    }

    /// @dev UUPS upgrade authorization hook; restricted to the owner.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev Reverts if the caller is not the gateway.
    function _requireGateway() internal view {
        if (msg.sender != address(GATEWAY)) {
            revert CallerIsNotGateway(msg.sender);
        }
    }

    /// @dev Reverts if the caller is not the WatchTower.
    function _requireWatchTower() internal view {
        if (msg.sender != address(WATCHTOWER)) {
            revert NotWatchTower(msg.sender);
        }
    }
}
