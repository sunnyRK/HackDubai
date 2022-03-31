# stableAPY
Automated market making strategy for stablecoins using the 1inch Limit Order Protocol

## Installation

Clone the repository

```bash
$ git clone https://github.com/sunnyRK/HackDubai
$ cd HackDubai
```

```bash
$ yarn start # to start a development
$ yarn build # to create a production build
```

## How it works
user depoist DAI in to the contract, and get leverage bearing token, stableAPY use 1inch limit order and create two order 
1. swap dai with USDC where taking amount is 0.99 USDC(arbitrary number). 
2. swap USDC with dai where taking amount is 0.99 DAI (rbitrary number). 
we can do this multiple time in loop 

## example
1000 dai in pool 
using 1inch limit order we create order buy usdc 1dai = 0.99usdc 
there for balance is 1010USDC
then we put another order will be 1 USDC == 0.99 DAI 
therefor balance is 1020
we autometed this infinity time.

