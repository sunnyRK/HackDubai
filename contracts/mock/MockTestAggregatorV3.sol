// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.0;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MockTestAggregatorV3 is AggregatorV3Interface {
    uint8 public _newdecimals;
    uint80 public _roundId;
    int256 public _answer;
    uint256 public _startedAt;
    uint256 public _updatedAt;
    uint80 public _answeredInRound;

    function decimals() external view override returns (uint8) {
        return _newdecimals;
    }

    function description() external view override returns (string memory _description) {}

    function version() external view override returns (uint256 _version) {}

    function setDecimals(uint8 _decimals) public {
        _newdecimals = _decimals;
    }

    function setLatestRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        _roundId = roundId;
        _answer = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function getPrice(uint256 _twapInterval) external view returns (uint256 answer) {
        answer = uint256(_answer);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = _roundId;
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
        answeredInRound = _answeredInRound;
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = _roundId;
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
        answeredInRound = _answeredInRound;
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
