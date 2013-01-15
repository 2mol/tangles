module Math.KnotTh.Tangle.Moves.ReidemeisterIII
    ( neighbours
    ) where

import Data.Maybe
import Control.Monad (guard)
import Math.KnotTh.Tangle.NonAlternating
import Math.KnotTh.Tangle.Moves.Move


neighbours :: NonAlternatingTangle -> [NonAlternatingTangle]
neighbours tangle = mapMaybe try3rdReidemeister $ allDartsOfCrossings tangle
    where
        -- \sc           /rb             \sc   /rb
        --  \           /                 \   /
        -- cs\ cb   bc /br               ac\ /ab
        -- ---------------                  /
        --   ca\c   b/ba                 ap/a\aq
        --      \   /         -->         /   \
        --     ac\ /ab                 cs/c   b\br
        --        /                  ---------------
        --     ap/a\aq               ca/ cb   bc \ba
        --      /   \                 /           \
        --   pa/     \qa             /pa           \qa
        try3rdReidemeister ab = do
            guard $ isDart ab

            let ac = nextCCW ab
                ba = opposite ab
                ca = opposite ac

            guard $ isDart ba && isDart ca

            let bc = nextCW ba
                cb = nextCCW ca

            guard $ bc == opposite cb

            let a = incidentCrossing ab
                b = incidentCrossing ba
                c = incidentCrossing ca

            guard $ (a /= b) && (a /= c) && (b /= c)
            guard $ (passOver bc) == (passOver cb)

            guard $
                let altRoot
                        | passOver ab == passOver ba  = ca
                        | otherwise                   = bc
                in ab < altRoot

            let ap = threadContinuation ab
                aq = nextCW ab
                br = nextCW bc
                cs = nextCCW cb

            return $! move tangle $ do
                substituteC [(ca, ap), (ba, aq), (ab, br), (ac, cs)]
                connectC [(br, aq), (cs, ap)]
