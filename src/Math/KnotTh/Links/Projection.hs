module Math.KnotTh.Links.Projection
	( module Math.KnotTh.Crossings
	, module Math.KnotTh.Crossings.Projection
	, module Math.KnotTh.Links
	, LinkProjection
	, linkProjection
	) where

import Math.KnotTh.Crossings
import Math.KnotTh.Crossings.Projection
import Math.KnotTh.Links


type LinkProjection = Link ProjectionCrossing


linkProjection :: Link ct -> LinkProjection
linkProjection = mapCrossingStates (const projectionCrossing)