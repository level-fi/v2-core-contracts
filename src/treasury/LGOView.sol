// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LGOView is Ownable {
    uint256 public constant LGO_MAX_SUPPLY = 1000 ether;

    IERC20 public LGO;
    uint256 public totalEmission;

    constructor(address _lgo, uint256 _emission) {
        if (_lgo == address(0)) revert ZeroAddress();
        if (_emission > LGO_MAX_SUPPLY) revert EmissionTooHigh();
        LGO = IERC20(_lgo);
        totalEmission = _emission;
        emit EmissionAdded(_emission);
    }

    // =============== VIEW FUNCTIONS ===============
    function getBurnedLGOAmount() public view returns (uint256) {
        return _getBurnedLGOAmount();
    }

    function estimatedLGOCirculatingSupply() external view returns (uint256 _circulatingSupply) {
        uint256 _burnedAmount = _getBurnedLGOAmount();
        if (totalEmission > _burnedAmount) {
            _circulatingSupply = totalEmission - _burnedAmount;
        }
        if (_circulatingSupply > LGO_MAX_SUPPLY) {
            _circulatingSupply = LGO_MAX_SUPPLY;
        }
    }

    // =============== USER FUNCTIONS ===============
    function addEmission(uint256 _emission) external {
        if (msg.sender != owner()) revert Unauthorized();
        totalEmission += _emission;
        emit EmissionAdded(_emission);
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _getBurnedLGOAmount() internal view returns (uint256) {
        uint256 _lgoTotalSupply = LGO.totalSupply();
        return LGO_MAX_SUPPLY > _lgoTotalSupply ? LGO_MAX_SUPPLY - _lgoTotalSupply : 0;
    }

    // =============== ERRORS ===============
    error ZeroAddress();
    error EmissionTooHigh();
    error Unauthorized();

    // =============== EVENTS ===============
    event EmissionAdded(uint256 _emission);
}
