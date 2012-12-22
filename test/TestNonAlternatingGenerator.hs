module Main (main) where

import Data.Ord
import Data.Function (on)
import Data.List (sortBy, groupBy)
import Control.Monad
import Math.KnotTh.Tangle.BorderIncremental.SimpleTypes
import Math.KnotTh.Enumeration.Applied.NonAlternatingTangles
import Math.KnotTh.Tangle.Draw
import Math.KnotTh.Link.FromTangle
import Math.KnotTh.Invariants.Skein.JonesPolynomial
import Math.KnotTh.Invariants.ThreadExpansion
import Math.KnotTh.Invariants.LinkingNumber
import Graphics.HP
import Tests.Table


main :: IO ()
main = do
	let diagrams n yield =
		simpleIncrementalGenerator
			(triangleBoundedType n primeIrreducibleDiagramType)
			[ArbitraryCrossing]
			n
			(\ t _ -> yield t)

	printTable "Diagrams" $ generateTable' $ diagrams 5

	let classes = tangleClasses (diagrams 7) :: [MinimalDiagramInfo NonAlternatingTangle]
	let sifted = siftTangles classes
	print $ length $ snd sifted

	--let invariant tangle =
		--let inv t = (linkingNumber t, jonesPolynomialOfTangle t)
		--in min (inv tangle) (inv $ invertCrossings tangle)
	--	(linkingNumbersOfTangle tangle, min (jonesPolynomialOfTangle tangle) (jonesPolynomialOfTangle $ invertCrossings tangle))

	{-forM_ tc $ \ cl -> do
		let l = map invariant $ allDiagrams cl
		let ok = all (== head l) l
		when (not ok) $ do
			putStrLn "FFFUUUUUU-"
			print l
			writePostScriptFile "fuuu.ps" $ do
				let a4Width = 595
				let a4Height = 842
				transformed [shifted (0.05 * a4Width, 0.98 * a4Height), scaled 10] $ do
					forM_ (allDiagrams cl) $ \ t -> do
						drawTangle 0.02 t
						appendTransform [shifted (0, -2.2)]
		return ()
	--print $ length $ snd tc
-}
	return ()

{-	let classes maxN = siftWeakTangleClasses $ \ yieldDiagram -> diagrams maxN (\ t _ -> yieldDiagram t)

	forM_ (classes 7) $ \ cl -> do
		let poly = map (jonesPolynomialOfLink' . tangleDoubling id) cl
		let ok = all (== head poly) poly
		print ok
-}
{-
	printTable "Arbitrary tangles" $ generateTable' $
		let generate n = forM_ (siftTangles $ \ yieldDiagram -> diagrams n (\ t _ -> yieldDiagram t))
		in generate 6

	let gen maxN = siftWeakTangles $ \ yieldDiagram -> diagrams maxN (\ t _ -> when (numberOfLegs t == 4) $ yieldDiagram t)
	let res = sortBy (comparing fst) $ map (\ t -> ((numberOfCrossings t, length $ allThreads t), t)) $ filter ((<= 7) . numberOfCrossings) $ gen 8
	forM_ res $ \ (i, t) -> do
		let p = jonesPolynomialOfLink $ tangleDoubling id t
		putStrLn $ show i ++ ": " ++ show p


	writePostScriptFile "tangles.ps" $ do
		let a4Width = 595
		let a4Height = 842

		transformed [shifted (0.05 * a4Width, 0.98 * a4Height), scaled 10] $ do
			--let classes = siftByEquivalenceClasses (++) ((: []) . fst)
			--	(\ (t, c) -> min (isomorphismTest (t, c)) (isomorphismTest (invertCrossings t, c)))
			--	[]
			--	(\ yieldDiagram -> simpleIncrementalGenerator primeIrreducibleDiagramType [ArbitraryCrossing] 3 (\ t _ -> yieldDiagram t))

			--forM_ classes $ \ tangles -> do
			--	forM_ (zip tangles [0 ..]) $ \ (tangle, i) ->
			--		transformed [shifted (2.2 * i, 0)] $ drawTangle 0.01 tangle
			--	appendTransform [shifted (0, -2.2)]

			--simpleIncrementalGenerator primeIrreducibleDiagramType [ArbitraryCrossing] 4 $ \ tangle _ ->
			--	when (numberOfLegs tangle == 4) $ do
			--		drawTangle 0.01 tangle
			--		let children = map ReidemeisterReduction.greedy1st2ndReduction $ concatMap ($ tangle) [ReidemeisterIII.neighbours, Flype.neighbours, Pass.neighbours]
			--		forM_ (zip (map fst $ children) [2 ..]) $ \ (res, i) ->
			--			transformed [shifted (2.2 * i, 0)] $ drawTangle 0.01 res
			--		appendTransform [shifted (0, -2.2)]

			forM_ (groupBy (on (==) fst) res) $ \ gr -> do
				forM_ (zip gr [0 ..]) $ \ ((_, tangle), i) ->
					transformed [shifted (2.2 * i, 0)] $ drawTangle 0.01 tangle
				appendTransform [shifted (0, -2.2)]
-}