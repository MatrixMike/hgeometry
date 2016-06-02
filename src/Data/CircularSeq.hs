module Data.CircularSeq( CSeq
                       , cseq
                       , singleton
                       , fromNonEmpty
                       , fromList

                       , focus

                       , rotateL
                       , rotateR
                       , rotateNL, rotateNR

                       , rightElements
                       , leftElements
                       , asSeq

                       , reverseDirection
                       , allRotations'

                       , findRotateTo
                       , rotateTo

                       ) where

import           Control.Applicative
import qualified Data.List.NonEmpty as NonEmpty
import           Data.Maybe (listToMaybe)
import           Data.Semigroup
import           Data.Semigroup.Foldable
import qualified Data.Sequence as S
import           Data.Sequence ((|>),(<|),ViewL(..),ViewR(..),Seq)
import qualified Data.Traversable as T
import qualified Data.Foldable as F
import           Data.Tuple (swap)

--------------------------------------------------------------------------------

-- | Nonempty circular sequence
data CSeq a = CSeq !(Seq a) !a !(Seq a)
            deriving (Eq)
                     -- we keep the seq balanced, i.e. size left >= size right

instance Show a => Show (CSeq a) where
  showsPrec d s = showParen (d > app_prec) $
                    showString (("CSeq " <>) . show . F.toList . rightElements $ s)
    where app_prec = 10

-- traverses starting at the focus, going to the right.
instance T.Traversable CSeq where
  traverse f (CSeq l x r) = (\x' r' l' -> CSeq l' x' r')
                         <$> f x <*> traverse f r <*> traverse f l

instance F.Foldable CSeq where
  foldMap = T.foldMapDefault
  length (CSeq l _ r) = 1 + S.length l + S.length r


instance Functor CSeq where
  fmap = T.fmapDefault


singleton   :: a -> CSeq a
singleton x = CSeq S.empty x S.empty

-- | Gets the focus of the CSeq
-- running time: O(1)
focus              :: CSeq a -> a
focus (CSeq _ x _) = x


resplit   :: Seq a -> (Seq a, Seq a)
resplit s = swap $ S.splitAt (length s `div` 2) s


-- | smart constructor that automatically balances the seq
cseq                   :: Seq a -> a -> Seq a -> CSeq a
cseq l x r
    | ln > 1 + 2*rn    = withFocus x (r <> l)
    | ln < rn `div`  2 = withFocus x (r <> l)
    | otherwise        = CSeq l x r
  where
    rn = length r
    ln = length l

-- | Builds a balanced seq with the element as the focus.
withFocus     :: a -> Seq a -> CSeq a
withFocus x s = let (l,r) = resplit s in CSeq l x r

-- | rotates one to the right
--
-- running time: O(1) (amortized)
--
-- >>> rotateR $ fromList [3,4,5,1,2]
-- CSeq [4,5,1,2,3]
rotateR                :: CSeq a -> CSeq a
rotateR s@(CSeq l x r) = case S.viewl r of
                           EmptyL    -> case S.viewl l of
                             EmptyL    -> s
                             (y :< l') -> cseq (S.singleton x) y l'
                           (y :< r') -> cseq (l |> x) y r'

-- | rotates the focus to the left
--
-- running time: O(1) (amortized)
--
-- >>> rotateL $ fromList [3,4,5,1,2]
-- CSeq [2,3,4,5,1]
-- >>> mapM_ print . take 5 $ iterate rotateL $ fromList [1..5]
-- CSeq [1,2,3,4,5]
-- CSeq [5,1,2,3,4]
-- CSeq [4,5,1,2,3]
-- CSeq [3,4,5,1,2]
-- CSeq [2,3,4,5,1]
rotateL                :: CSeq a -> CSeq a
rotateL s@(CSeq l x r) = case S.viewr l of
                           EmptyR    -> case S.viewr r of
                             EmptyR     -> s
                             (r' :> y)  -> cseq r' y (S.singleton x)
                           (l' :> y) -> cseq l' y (x <| r)


-- | Convert to a single Seq, starting with the focus.
asSeq :: CSeq a -> Seq a
asSeq = rightElements


-- | All elements, starting with the focus, going to the right

-- >>> rightElements $ fromList [3,4,5,1,2]
-- fromList [3,4,5,1,2]
rightElements              :: CSeq a -> Seq a
rightElements (CSeq l x r) = x <| r <> l


-- | All elements, starting with the focus, going to the left
--
-- >>> leftElements $ fromList [3,4,5,1,2]
-- fromList [3,2,1,5,4]
leftElements              :: CSeq a -> Seq a
leftElements (CSeq l x r) = x <| S.reverse l <> S.reverse r

-- | builds a CSeq
fromNonEmpty                    :: NonEmpty.NonEmpty a -> CSeq a
fromNonEmpty (x NonEmpty.:| xs) = withFocus x $ S.fromList xs

fromList        :: [a] -> CSeq a
fromList (x:xs) = withFocus x $ S.fromList xs
fromList []     = error "fromList: Empty list"

-- | Rotates i elements to the right.
--
-- pre: 0 <= i < n
--
-- running time: $O(\log i)$ amortized
--
-- >>> rotateNR 0 $ fromList [1..5]
-- CSeq [1,2,3,4,5]
-- >>> rotateNR 1 $ fromList [1..5]
-- CSeq [2,3,4,5,1]
-- >>> rotateNR 4 $ fromList [1..5]
-- CSeq [5,1,2,3,4]
rotateNR     :: Int -> CSeq a -> CSeq a
rotateNR i s = let (l, r')  = S.splitAt i $ rightElements s
                   (x :< r) = S.viewl r'
               in cseq l x r


-- | Rotates i elements to the left.
--
-- pre: 0 <= i < n
--
-- running time: $O(\log i)$ amoritzed
--
-- >>> rotateNL 0 $ fromList [1..5]
-- CSeq [1,2,3,4,5]
-- >>> rotateNL 1 $ fromList [1..5]
-- CSeq [5,1,2,3,4]
-- >>> rotateNL 2 $ fromList [1..5]
-- CSeq [4,5,1,2,3]
-- >>> rotateNL 3 $ fromList [1..5]
-- CSeq [3,4,5,1,2]
-- >>> rotateNL 4 $ fromList [1..5]
-- CSeq [2,3,4,5,1]
rotateNL     :: Int -> CSeq a -> CSeq a
rotateNL i s = let (x :< xs) = S.viewl $ rightElements s
                   (l',r)    = S.splitAt (length s - i) $ xs |> x
                   (l :> y)  = S.viewr l'
               in cseq l y r


-- | Reversres the direction of the CSeq
--
-- running time: $O(n)$
--
-- >>> reverseDirection $ fromList [1..5]
-- CSeq [1,5,4,3,2]
reverseDirection              :: CSeq a -> CSeq a
reverseDirection (CSeq l x r) = CSeq (S.reverse r) x (S.reverse l)


-- | Finds an element in the CSeq
--
-- >>> findRotateTo (== 3) $ fromList [1..5]
-- Just (CSeq [3,4,5,1,2])
-- >>> findRotateTo (== 7) $ fromList [1..5]
-- Nothing
findRotateTo   :: (a -> Bool) -> CSeq a -> Maybe (CSeq a)
findRotateTo p = listToMaybe . filter (p . focus) . allRotations'


rotateTo x = findRotateTo (== x)


-- | All rotations, the input CSeq is the focus.
--
-- >>> mapM_ print . allRotations $ fromList [1..5]
-- CSeq [1,2,3,4,5]
-- CSeq [2,3,4,5,1]
-- CSeq [3,4,5,1,2]
-- CSeq [4,5,1,2,3]
-- CSeq [5,1,2,3,4]
allRotations :: CSeq a -> CSeq (CSeq a)
allRotations = fromList . allRotations'

allRotations'   :: CSeq a -> [CSeq a]
allRotations' s = take (length s) . iterate rotateR $ s
