package stagedsync

import (
	"fmt"
	"sync/atomic"

	"github.com/ledgerwatch/erigon-lib/kv"
	"github.com/ledgerwatch/erigon/consensus"
	"github.com/ledgerwatch/erigon/core/rawdb"
	"github.com/ledgerwatch/erigon/core/types"
	"github.com/ledgerwatch/erigon/params"
	"github.com/ledgerwatch/log/v3"
)

type MiningFinishCfg struct {
	db             kv.RwDB
	chainConfig    params.ChainConfig
	engine         consensus.Engine
	sealCancel     <-chan struct{}
	miningState    MiningState
	assembledBlock *atomic.Value
}

func StageMiningFinishCfg(
	db kv.RwDB,
	chainConfig params.ChainConfig,
	engine consensus.Engine,
	miningState MiningState,
	sealCancel <-chan struct{},
	assembledBlock *atomic.Value,
) MiningFinishCfg {
	return MiningFinishCfg{
		db:             db,
		chainConfig:    chainConfig,
		engine:         engine,
		miningState:    miningState,
		sealCancel:     sealCancel,
		assembledBlock: assembledBlock,
	}
}

func SpawnMiningFinishStage(s *StageState, tx kv.RwTx, cfg MiningFinishCfg, quit <-chan struct{}) error {
	logPrefix := s.LogPrefix()
	current := cfg.miningState.MiningBlock
	// Short circuit when receiving duplicate result caused by resubmitting.
	//if w.chain.HasBlock(block.Hash(), block.NumberU64()) {
	//	continue
	//}

	isTrans, err := rawdb.Transitioned(tx, current.Header.Number.Uint64()-1, cfg.chainConfig.TerminalTotalDifficulty)
	if err != nil {
		return err
	}

	// If we are on proof-of-stake, we send our block to the engine API
	if isTrans {
		cfg.assembledBlock.Store(types.NewBlock(current.Header, current.Txs, nil, current.Receipts))
		return nil
	}

	block := types.NewBlock(current.Header, current.Txs, current.Uncles, current.Receipts)
	*current = MiningBlock{} // hack to clean global data
	//sealHash := engine.SealHash(block.Header())
	// Reject duplicate sealing work due to resubmitting.
	//if sealHash == prev {
	//	s.Done()
	//	return nil
	//}
	//prev = sealHash

	// Tests may set pre-calculated nonce
	if block.NonceU64() != 0 {
		cfg.miningState.MiningResultCh <- block
		return nil
	}

	cfg.miningState.PendingResultCh <- block

	if block.Transactions().Len() > 0 {
		log.Info(fmt.Sprintf("[%s] block ready for seal", logPrefix),
			"blocn_num", block.NumberU64(),
			"transactions", block.Transactions().Len(),
			"gas_used", block.GasUsed(),
			"gas_limit", block.GasLimit(),
			"difficulty", block.Difficulty(),
		)
	}

	chain := ChainReader{Cfg: cfg.chainConfig, Db: tx}
	if err := cfg.engine.Seal(chain, block, cfg.miningState.MiningResultCh, cfg.sealCancel); err != nil {
		log.Warn("Block sealing failed", "err", err)
	}

	return nil
}
