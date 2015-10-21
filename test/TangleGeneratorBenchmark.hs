{-# LANGUAGE RankNTypes #-}
module Main (main) where

import Control.Monad.State (execState, modify)
import Control.Monad (when)
import Diagrams.Prelude
import Diagrams.Backend.SVG
import Math.Topology.KnotTh.Tangle
import Math.Topology.KnotTh.Draw
import Math.Topology.KnotTh.Tabulation.TangleDiagramsCascade
import Math.Topology.KnotTh.Tabulation.TangleFlypeClasses
import TestUtil.Table


main :: IO ()
main = do
    printTable "Prime projections"    $ generateTable $ forCCP_ (primeProjections 8)
    printTable "Template projections" $ generateTable $ forCCP_ (templateProjections 9)
    printTable "Alternating tangles"  $ generateTable $ generateFlypeEquivalent 8
    printTable "Prime diagrams"       $ generateTable $ forCCP_ (primeDiagrams 6)
    printTable "Prime irr. diagrams"  $ generateTable $ forCCP_ (primeIrreducibleDiagrams 6)

    renderSVG "tangles.svg" (mkSizeSpec $ V2 (Just 256) Nothing) $ pad 1.05 $ flip execState mempty $
        forCCP_ (primeIrreducibleDiagrams 3) $ \ (tangle, _) ->
            when (numberOfLegs tangle == 4) $
                modify (=== pad 1.1 (drawKnotDef tangle))
