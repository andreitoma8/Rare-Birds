from brownie import (
    chain,
    accounts,
    RareBirdsGenOne,
    RareBirdsGenTwo,
    ElementalStones,
    ElementalBirdsGenOne,
    MingoToken,
)
import brownie


def test_main():
    # Set up
    owner = accounts[0]
    mingo = MingoToken.deploy({"from": owner})
    rare_one = RareBirdsGenOne.deploy(mingo.address, {"from": owner})
    approve = mingo.approve(rare_one.address, 100000 * 10 ** 18, {"from": owner})
    unpause = rare_one.setPaused(False, {"from": owner})
    # Mint 2 NFTs
    mint = rare_one.mint(2, {"from": owner})
    balance = rare_one.balanceOf(owner.address, {"from": owner})
    assert balance == 2
    # Assert if NFTs are eggs
    token_1_state = rare_one.isBird(1, {"from": owner})
    token_2_state = rare_one.isBird(2, {"from": owner})
    assert token_1_state == token_2_state == False
    # Stake
    stake = rare_one.stake([1, 2], {"from": owner})
    stake_info = rare_one.userStakeInfo(owner.address, {"from": owner})
    assert stake_info[1] == [1, 2]
    # Assert error if trying to hash or breed
    with brownie.reverts():
        rare_one.hatchEgg(1, True, {"from": owner})
    with brownie.reverts():
        rare_one.hatchEgg(1, False, {"from": owner})
    with brownie.reverts():
        rare_one.breed(0, {"from": owner})
    with brownie.reverts():
        rare_one.breed(1, {"from": owner})
    # Forward in time
    chain.mine(blocks=100, timedelta=2593000)
    # Assert rewards accumulation
    stake_info = rare_one.userStakeInfo(owner.address, {"from": owner})
    print(stake_info)
    print((2593000 * 2 * 100000) / 3600)
    assert stake_info[0] >= (2593000 * 2 * 100000) / 3600
    # Assert hatching
    hatch = rare_one.hatchEgg(1, False, {"from": owner})
    breeding_state = rare_one.breedingState(owner.address, {"from": owner})
    assert breeding_state[0] == False
    hatched_state_1 = rare_one.isBird(1, {"from": owner})
    hatched_state_2 = rare_one.isBird(2, {"from": owner})
    assert hatched_state_1 == True and hatched_state_2 == False
    hatch = rare_one.hatchEgg(2, True, {"from": owner})
    hatched_state_1 = rare_one.isBird(1, {"from": owner})
    hatched_state_2 = rare_one.isBird(2, {"from": owner})
    assert hatched_state_1 == hatched_state_2 == True
    # Assert breeding start after owner has 2 birds
    breeding_state = rare_one.breedingState(owner.address, {"from": owner})
    assert breeding_state[0] == True
    # Forward in time
    chain.mine(blocks=100, timedelta=2593000)
    # Deploy Gen. 2
    rare_two = RareBirdsGenTwo.deploy(mingo.address, rare_one.address, {"from": owner})
    rare_one.setNextGen(rare_two.address, {"from": owner})
    # Deploy Elemental Stones
    stones = ElementalStones.deploy(mingo.address, {"from": owner})
    rare_one.setElementalStones(stones.address, {"from": owner})
    rare_two.setElementalStones(stones.address, {"from": owner})
    # Deploy Elemental Birds
    elem_one = ElementalBirdsGenOne.deploy(
        mingo.address, rare_one.address, {"from": owner}
    )
    rare_one.setElementalBirdsGen1(elem_one.address, {"from": owner})
    # Breed for Gen. 2
    rare_one.breed(0, {"from": owner})
    with brownie.reverts():
        rare_one.breed(0, {"from": owner})
    balance_gen_2 = rare_two.balanceOf(owner.address, {"from": owner})
    assert balance_gen_2 == 1
    # Forward in time
    chain.mine(blocks=100, timedelta=2593000)
    # Mint Elemental Stone
    approve = mingo.approve(stones.address, 100000 * 10 ** 18, {"from": owner})
    stones.setPaused(False, {"from": owner})
    stones.mint(1, 1, False, {"from": owner})
    tokens_of_owner = stones.walletOfOwner(owner.address, {"from": owner})
    print(tokens_of_owner)
    # Breed for Elemental Birds Gen. 1
    stones.approve(rare_one.address, 1, {"from": owner})
    rare_one.breed(1, {"from": owner})
    tokens_of_owner = elem_one.walletOfOwner(owner.address, {"from": owner})
    assert tokens_of_owner[0] == 1
    # Assert rewards accumulation
    stake_info = rare_one.userStakeInfo(owner.address, {"from": owner})
    print(stake_info)
    print((2593000 * 2 * 100000) * 3 / 3600)
    assert stake_info[0] >= (2593000 * 2 * 100000) * 3 / 3600
