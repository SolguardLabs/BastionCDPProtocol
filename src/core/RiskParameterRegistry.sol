// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract RiskParameterRegistry is BastionAccessControl {
    error UnknownTemplate();
    error TemplateExists();
    error InvalidTemplate();

    struct RiskTemplate {
        bytes32 id;
        bool enabled;
        uint256 debtCeiling;
        uint256 minDebt;
        uint256 liquidationRatioBps;
        uint256 liquidationPenaltyBps;
        uint256 maxPriceAge;
        uint256 auctionDiscountBps;
        uint256 closeFactorBps;
        string label;
    }

    bytes32[] private _templateIds;
    mapping(bytes32 id => RiskTemplate template_) private _templates;

    event RiskTemplateCreated(bytes32 indexed id, string label);
    event RiskTemplateUpdated(bytes32 indexed id, bool enabled);
    event RiskTemplateDisabled(bytes32 indexed id);

    constructor(
        address initialOwner
    ) BastionAccessControl(initialOwner) { }

    function createTemplate(
        RiskTemplate calldata template_
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        _validate(template_);
        if (_templates[template_.id].id != bytes32(0)) revert TemplateExists();

        _templates[template_.id] = template_;
        _templateIds.push(template_.id);

        emit RiskTemplateCreated(template_.id, template_.label);
    }

    function updateTemplate(
        RiskTemplate calldata template_
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        _validate(template_);
        if (_templates[template_.id].id == bytes32(0)) revert UnknownTemplate();

        _templates[template_.id] = template_;

        emit RiskTemplateUpdated(template_.id, template_.enabled);
    }

    function disableTemplate(
        bytes32 id
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        RiskTemplate storage template_ = _templates[id];
        if (template_.id == bytes32(0)) revert UnknownTemplate();

        template_.enabled = false;

        emit RiskTemplateDisabled(id);
    }

    function templateCount() external view returns (uint256) {
        return _templateIds.length;
    }

    function templateIdAt(
        uint256 index
    ) external view returns (bytes32) {
        return _templateIds[index];
    }

    function getTemplate(
        bytes32 id
    ) external view returns (RiskTemplate memory) {
        RiskTemplate memory template_ = _templates[id];
        if (template_.id == bytes32(0)) revert UnknownTemplate();
        return template_;
    }

    function buildCollateralConfig(
        bytes32 id,
        address collateralToken,
        address oracle,
        string calldata symbol
    ) external view returns (BastionTypes.CollateralConfig memory) {
        RiskTemplate memory template_ = _templates[id];
        if (template_.id == bytes32(0)) revert UnknownTemplate();

        return BastionTypes.CollateralConfig({
            enabled: template_.enabled,
            token: collateralToken,
            oracle: oracle,
            debtCeiling: template_.debtCeiling,
            minDebt: template_.minDebt,
            liquidationRatioBps: template_.liquidationRatioBps,
            liquidationPenaltyBps: template_.liquidationPenaltyBps,
            maxPriceAge: template_.maxPriceAge,
            auctionDiscountBps: template_.auctionDiscountBps,
            closeFactorBps: template_.closeFactorBps,
            symbol: symbol
        });
    }

    function conservativeTemplate(
        bytes32 id,
        string calldata label
    ) external pure returns (RiskTemplate memory) {
        return RiskTemplate({
            id: id,
            enabled: true,
            debtCeiling: 2_000_000e18,
            minDebt: 1000e18,
            liquidationRatioBps: 17_500,
            liquidationPenaltyBps: 1500,
            maxPriceAge: 30 minutes,
            auctionDiscountBps: 300,
            closeFactorBps: 7500,
            label: label
        });
    }

    function balancedTemplate(
        bytes32 id,
        string calldata label
    ) external pure returns (RiskTemplate memory) {
        return RiskTemplate({
            id: id,
            enabled: true,
            debtCeiling: 10_000_000e18,
            minDebt: 500e18,
            liquidationRatioBps: 15_000,
            liquidationPenaltyBps: 1300,
            maxPriceAge: 1 hours,
            auctionDiscountBps: 500,
            closeFactorBps: 10_000,
            label: label
        });
    }

    function aggressiveTemplate(
        bytes32 id,
        string calldata label
    ) external pure returns (RiskTemplate memory) {
        return RiskTemplate({
            id: id,
            enabled: true,
            debtCeiling: 25_000_000e18,
            minDebt: 250e18,
            liquidationRatioBps: 13_000,
            liquidationPenaltyBps: 1000,
            maxPriceAge: 20 minutes,
            auctionDiscountBps: 700,
            closeFactorBps: 10_000,
            label: label
        });
    }

    function _validate(
        RiskTemplate calldata template_
    ) internal pure {
        if (template_.id == bytes32(0)) revert InvalidTemplate();
        if (template_.debtCeiling == 0) revert InvalidTemplate();
        if (template_.minDebt == 0 || template_.minDebt >= template_.debtCeiling) {
            revert InvalidTemplate();
        }
        if (template_.liquidationRatioBps < BastionTypes.BPS) revert InvalidTemplate();
        if (template_.liquidationPenaltyBps > 5000) revert InvalidTemplate();
        if (template_.maxPriceAge == 0) revert InvalidTemplate();
        if (template_.auctionDiscountBps > 5000) revert InvalidTemplate();
        if (template_.closeFactorBps > BastionTypes.BPS) revert InvalidTemplate();
    }
}
