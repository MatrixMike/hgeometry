{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE UndecidableInstances  #-}
module Data.Geometry.SubLine where

import           Control.Lens
import           Data.Ext
import qualified Data.Foldable as F
import           Data.Geometry.Interval
import           Data.Geometry.Line.Internal
import           Data.Geometry.Point
import           Data.Geometry.Properties
import           Data.Geometry.Vector
import qualified Data.Traversable as T
import           Data.UnBounded
import           Data.Vinyl
import           Data.Vinyl.CoRec

--------------------------------------------------------------------------------

-- | Part of a line. The interval is ranged based on the vector of the
-- line l, and s.t.t zero is the anchorPoint of l.
data SubLine d p r = SubLine { _line     :: Line d r
                             , _subRange :: Interval p r
                             }


makeLenses ''SubLine

type instance Dimension (SubLine d p r) = d
type instance NumType   (SubLine d p r) = r

deriving instance (Show r, Show p, Arity d) => Show (SubLine d p r)
deriving instance (Eq r, Eq p, Arity d)     => Eq (SubLine d p r)
deriving instance Arity d                   => Functor (SubLine d p)
deriving instance Arity d                   => F.Foldable (SubLine d p)
deriving instance Arity d                   => T.Traversable (SubLine d p)

instance Arity d => Bifunctor (SubLine d) where
  bimap f g (SubLine l r) = SubLine (g <$> l) (bimap f g r)


-- | Get the point at the given position along line, where 0 corresponds to the
-- anchorPoint of the line, and 1 to the point anchorPoint .+^ directionVector
pointAt              :: (Num r, Arity d) => r -> Line d r -> Point d r
pointAt a (Line p v) = p .+^ (a *^ v)



-- | Annotate the subRange with the actual ending points
fixEndPoints    :: (Num r, Arity d) => SubLine d p r -> SubLine d (Point d r :+ p) r
fixEndPoints sl = sl&subRange %~ f
  where
    ptAt              = flip pointAt (sl^.line)
    label (c :+ e)    = (c :+ (ptAt c :+ e))
    f ~(Interval l u) = Interval (l&unEndPoint %~ label)
                                 (u&unEndPoint %~ label)


-- | given point p on line (Line q v), Get the scalar lambda s.t.
-- p = q + lambda v
toOffset              :: (Eq r, Fractional r, Arity d) => Point d r -> Line d r -> r
toOffset p (Line q v) = fromJust' $ scalarMultiple (p .-. q) v
  where
    fromJust' (Just x) = x
    fromJust' _        = error "toOffset: Nothing"

type instance IntersectionOf (SubLine 2 p r) (SubLine 2 q r) = [ NoIntersection
                                                               , Point 2 r
                                                               , SubLine 2 p r
                                                               ]

-- | given point p, and a Subline l r such that p lies on line l, test if it
-- lies on the subline, i.e. in the interval r
onSubLine                 :: (Ord r, Fractional r, Arity d)
                          => Point d r -> SubLine d p r -> Bool
onSubLine p (SubLine l r) = toOffset p l `inInterval` r

-- | given point p, and a Subline l r such that p lies on line l, test if it
-- lies on the subline, i.e. in the interval r
onSubLine2        :: (Ord r, Num r) => Point 2 r -> SubLine 2 p r -> Bool
p `onSubLine2` sl = d `inInterval` r
  where
    -- get the endpoints (a,b) of the subline
    SubLine _ (Interval s e) = fixEndPoints sl
    a = s^.unEndPoint.extra.core
    b = e^.unEndPoint.extra.core
    d = (p .-. a) `dot` (b .-. a)
    -- map to an interval corresponding to the length of the segment
    r = Interval (s&unEndPoint.core .~ 0) (e&unEndPoint.core .~ squaredEuclideanDist b a)
      -- note that we take the dist between b and a, so if these are infinity
      -- we get maxInfinity as well

instance (Ord r, Fractional r) =>
         (SubLine 2 p r) `IsIntersectableWith` (SubLine 2 p r) where

  nonEmptyIntersection = defaultNonEmptyIntersection

  sl@(SubLine l r) `intersect` sm@(SubLine m _) = match (l `intersect` m) $
         (H $ \NoIntersection -> coRec NoIntersection)
      :& (H $ \p@(Point _)    -> if onSubLine2 p sl && onSubLine2 p sm
                                 then coRec p
                                 else coRec NoIntersection)
      :& (H $ \_             -> match (r `intersect` s'') $
                                      (H $ \NoIntersection -> coRec NoIntersection)
                                   :& (H $ \i              -> coRec $ SubLine l i)
                                   :& RNil
           )
      :& RNil
    where
      -- s' = shiftLeft' (toOffset (m^.anchorPoint) l) $ s
      s'  = (fixEndPoints sm)^.subRange
      s'' = bimap (^.extra) id
          $ s'&start.core .~ toOffset (s'^.start.extra.core) l
              &end.core   .~ toOffset (s'^.end.extra.core)   l

fromLine   :: Arity d => Line d r -> SubLine d () (UnBounded r)
fromLine l = SubLine (fmap Val l) (ClosedInterval (ext MinInfinity) (ext MaxInfinity))


-- testL :: SubLine 2 () (UnBounded Rational)
-- testL = SubLine (horizontalLine 0) (Interval (Closed (only 0)) (Open $ only 10))

-- horL :: SubLine 2 () (UnBounded Rational)
-- horL = fromLine $ horizontalLine 0


-- test = (testL^.subRange) `intersect` (horL^.subRange)
