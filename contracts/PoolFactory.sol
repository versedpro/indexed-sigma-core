pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { IPool } from "./balancer/IPool.sol";
import "./interfaces/IERC20.sol";
import "./lib/Create2.sol";
import {
  DelegateCallProxyManager
} from "./proxies/DelegateCallProxyManager.sol";
import {
  DelegateCallProxyManyToOne
} from "./proxies/DelegateCallProxyManyToOne.sol";
import { SafeERC20 } from "./openzeppelin/SafeERC20.sol";


contract PoolFactory {
/* ---  Constants  --- */

  bytes32 internal constant PROXY_CODEHASH
    = keccak256(type(DelegateCallProxyManyToOne).creationCode);

  bytes32 internal constant POOL_IMPLEMENTATION_ID
    = keccak256("IPool.sol");

  uint128 internal constant MAX_UINT_128 = 2**128 - 1;

  // Address of the NDX governance contract
  address internal immutable _ndx;
  // Address of the proxy manager contract.
  DelegateCallProxyManager internal immutable _proxyManager;

/* ---  Structs  --- */

  /**
   * @dev Data structure with the number of times a pool has been
   * either reweighed or re-indexed, as well as the timestamp of
   * the last such action.
   *
   * If `++index % REWEIGHS_BEFORE_REINDEX + 1` is 0, the pool will
   * re-index, otherwise it will reweigh.
   *
   * @param index Number of times the pool has either re-weighed or
   * re-indexed.
   * @param timestamp Timestamp of last pool re-weigh or re-index.
   */
  struct PoolUpdateRecord {
    uint128 index;
    uint128 timestamp;
  }

  /**
   * @dev Data structure with the tokens & balances for a pool
   * which has not yet been deployed.
   */
  struct PendingPool {
    address[] tokens;
    uint128[] balances;
  }

/* ---  Events  --- */

  event LOG_NEW_POOL(
    address indexed pool,
    address controller,
    bool approved
  );

/* ---  Storage  --- */

  mapping(address => bool) internal _approvedControllers;
  mapping(address => bool) internal _isIPool;

  bytes32 internal _publicImplementationId;

/* ---  Modifiers  --- */

  modifier _ndx_ {
    require(msg.sender == _ndx, "ERR_ONLY_OWNER");
    _;
  }

  modifier _approved_ {
    require(_approvedControllers[msg.sender], "ERR_NOT_APPROVED");
    _;
  }

  modifier _public_ {
    require(
      _publicImplementationId != bytes32(0),
      "ERR_NOT_PUBLIC"
    );
    _;
  }

/* ---  Constructor  --- */

  constructor(
    address ndx,
    DelegateCallProxyManager proxyManager
  ) public {
    _ndx = ndx;
    _proxyManager = proxyManager;
  }

/* ---  Controller Approval  --- */

  /** @dev Approves `controller` to deploy index pools. */
  function approvePoolController(address controller) external _ndx_ {
    _approvedControllers[controller] = true;
  }

  /** @dev Removes the ability of `controller` to deploy index pools. */
  function disapprovePoolController(address controller) external _ndx_ {
    _approvedControllers[controller] = false;
  }

/* ---  Pool Deployment  --- */

  /**
   * @dev Deploys an index pool and returns the address.
   *
   * Note: Does not initialize the pool, this must be executed
   * by the controller.
   *
   * Note: Must be called by an approved controller.
   *
   * @param suppliedSalt Create2 salt provided by the deployer
   * @param name Name of the index token - should indicate the category and size
   * @param symbol Symbol for the index token
   */
  function deployIndexPool(
    bytes32 suppliedSalt,
    string calldata name,
    string calldata symbol
  )
    external
    _approved_
    returns (address poolAddress)
  {
    bytes32 salt = keccak256(abi.encodePacked(
      msg.sender, suppliedSalt
    ));
    poolAddress = _proxyManager.deployProxyManyToOne(
      POOL_IMPLEMENTATION_ID,
      salt
    );
    _isIPool[poolAddress] = true;
    IPool(poolAddress).configure(
      msg.sender,
      name,
      symbol
    );
    emit LOG_NEW_POOL(poolAddress, msg.sender, true);
  }

  function deployIndexPool(
    bytes32 suppliedSalt,
    string calldata name,
    string calldata symbol,
    address[] calldata tokens,
    uint256[] calldata balances,
    uint96[] calldata denorms,
    address tokenProvider
  )
    external
    _public_
    returns (address poolAddress)
  {
    bytes32 salt = keccak256(abi.encodePacked(
     _publicImplementationId, msg.sender, suppliedSalt
    ));
    poolAddress = _proxyManager.deployProxyManyToOne(
      _publicImplementationId,
      salt
    );
    _isIPool[poolAddress] = true;
    PublicPoolImplementation(poolAddress).initialize(
      msg.sender,
      name,
      symbol,
      tokens,
      balances,
      denorms,
      tokenProvider
    );
    emit LOG_NEW_POOL(poolAddress, msg.sender, false);
  }

/* ---  Queries  --- */

  /**
   * @dev Checks if an address is an ipool.
   */
  function isIPool(address pool) external view returns (bool) {
    return _isIPool[pool];
  }

  /**
   * @dev Compute the create2 address for a pool deployed by an approved
   * indexed controller.
   */
  function computePoolAddress(address controller, bytes32 suppliedSalt)
    public
    view
    returns (address poolAddress)
  {
    bytes32 salt = keccak256(abi.encodePacked(
      controller, suppliedSalt
    ));
    poolAddress = Create2.computeAddress(
      salt, PROXY_CODEHASH, address(_proxyManager)
    );
  }

  /**
   * @dev Compute the create2 address for a pool deployed by a
   * non-approved controller.
   */
  function computePublicPoolAddress(address controller, bytes32 suppliedSalt)
    public
    view
    _public_
    returns (address poolAddress)
  {
    bytes32 salt = keccak256(abi.encodePacked(
     _publicImplementationId, controller, suppliedSalt
    ));
    poolAddress = Create2.computeAddress(
      salt, PROXY_CODEHASH, address(_proxyManager)
    );
  }

/* ---  Internal Utility Functions  --- */

  /**
   * @dev Re-assigns a uint128 array to a uint256 array.
   * This does not affect memory allocation as all Solidity
   * uint arrays take 32 bytes per item.
   */
  function _to256Array(uint128[] memory arr)
    internal
    pure
    returns (uint256[] memory outArr)
  {
    assembly {
      outArr := arr
    }
  }
}

/**
 * @dev Interface of the public pool implementation contract,
 * if the governance dao decides to make one available.
 */
interface PublicPoolImplementation {
  function initialize(
    address controller,
    string calldata name,
    string calldata symbol,
    address[] calldata tokens,
    uint256[] calldata balances,
    uint96[] calldata denorms,
    address tokenProvider
  ) external;
}