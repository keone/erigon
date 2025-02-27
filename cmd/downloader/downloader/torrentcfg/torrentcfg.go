package torrentcfg

import (
	"time"

	lg "github.com/anacrolix/log"
	"github.com/anacrolix/torrent"
	"github.com/c2h5oh/datasize"
	"github.com/ledgerwatch/erigon/p2p/nat"
	"github.com/ledgerwatch/log/v3"
	"golang.org/x/time/rate"
)

// DefaultPieceSize - Erigon serves many big files, bigger pieces will reduce
// amount of network announcements, but can't go over 2Mb
// see https://wiki.theory.org/BitTorrentSpecification#Metainfo_File_Structure
const DefaultPieceSize = 2 * 1024 * 1024

// DefaultNetworkChunkSize - how much data request per 1 network call to peer.
// default: 16Kb
// TODO: can we increase this value together with --torrent.upload.rate ?
const DefaultNetworkChunkSize = DefaultPieceSize

type Cfg struct {
	*torrent.ClientConfig
	//DB kv.RwDB
	//CompletionCloser io.Closer
	DownloadSlots int
}

func Default() *torrent.ClientConfig {
	torrentConfig := torrent.NewDefaultClientConfig()

	// enable dht
	torrentConfig.NoDHT = true
	//torrentConfig.DisableTrackers = true
	//torrentConfig.DisableWebtorrent = true
	//torrentConfig.DisableWebseeds = true

	// Reduce defaults - to avoid peers with very bad geography
	torrentConfig.MinDialTimeout = 1 * time.Second      // default: 3sec
	torrentConfig.NominalDialTimeout = 10 * time.Second // default: 20sec
	torrentConfig.HandshakesTimeout = 1 * time.Second   // default: 4sec

	return torrentConfig
}

func New(snapshotsDir string, verbosity lg.Level, natif nat.Interface, downloadRate, uploadRate datasize.ByteSize, port, connsPerFile int, downloadSlots int) (*Cfg, error) {
	torrentConfig := Default()
	// We would-like to reduce amount of goroutines in Erigon, so reducing next params
	torrentConfig.EstablishedConnsPerTorrent = connsPerFile // default: 50

	// see: https://en.wikipedia.org/wiki/TCP_half-open
	torrentConfig.TotalHalfOpenConns = 100     // default: 100
	torrentConfig.HalfOpenConnsPerTorrent = 25 // default: 25

	torrentConfig.TorrentPeersHighWater = 500 // default: 500
	torrentConfig.TorrentPeersLowWater = 50   // default: 50

	torrentConfig.ListenPort = port
	torrentConfig.Seed = true
	torrentConfig.DataDir = snapshotsDir
	torrentConfig.UpnpID = torrentConfig.UpnpID + "leecher"

	switch natif.(type) {
	case nil:
		// No NAT interface, do nothing.
	case nat.ExtIP:
		// ExtIP doesn't block, set the IP right away.
		ip, _ := natif.ExternalIP()
		torrentConfig.PublicIp4 = ip
		log.Info("[torrent] Public IP", "ip", torrentConfig.PublicIp4)
		// how to set ipv6?
		//torrentConfig.PublicIp6 = net.ParseIP(ip)

	default:
		// Ask the router about the IP. This takes a while and blocks startup,
		// do it in the background.
		if ip, err := natif.ExternalIP(); err == nil {
			torrentConfig.PublicIp4 = ip
			log.Info("[torrent] Public IP", "ip", torrentConfig.PublicIp4)
		}
	}
	// rates are divided by 2 - I don't know why it works, maybe bug inside torrent lib accounting
	torrentConfig.UploadRateLimiter = rate.NewLimiter(rate.Limit(uploadRate.Bytes()), 2*DefaultPieceSize) // default: unlimited
	if downloadRate.Bytes() < 500_000_000 {
		b := int(2 * DefaultPieceSize)
		if downloadRate.Bytes() > DefaultPieceSize {
			b = int(2 * downloadRate.Bytes())
		}
		torrentConfig.DownloadRateLimiter = rate.NewLimiter(rate.Limit(downloadRate.Bytes()), b) // default: unlimited
	}

	// debug
	if lg.Debug == verbosity {
		torrentConfig.Debug = true
	}
	torrentConfig.Logger = lg.Default.FilterLevel(verbosity)
	torrentConfig.Logger.Handlers = []lg.Handler{adapterHandler{}}

	return &Cfg{ClientConfig: torrentConfig, DownloadSlots: downloadSlots}, nil
}
