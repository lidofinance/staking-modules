// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC20Testable is ERC20 {
    constructor() ERC20("ERC20Testable", "TST") {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }
}

contract ERC721Testable is ERC721 {
    constructor() ERC721("ERC721Testable", "TST") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

contract ERC1155Testable is ERC1155 {
    constructor() ERC1155("") {}

    function mint(
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public {
        _mint(to, tokenId, amount, data);
    }
}
