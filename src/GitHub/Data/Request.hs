{-# LANGUAGE CPP                #-}
{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE KindSignatures     #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StandaloneDeriving #-}
-----------------------------------------------------------------------------
-- |
-- License     :  BSD-3-Clause
-- Maintainer  :  Oleg Grenrus <oleg.grenrus@iki.fi>
--
module GitHub.Data.Request (
    Request(..),
    CommandMethod(..),
    toMethod,
    StatusMap(..),
    MergeResult(..),
    Paths,
    IsPathPart(..),
    QueryString,
    Count,
    ) where

import Data.Aeson.Compat (FromJSON)
import Data.Hashable     (Hashable (..))
import Data.Typeable     (Typeable)
import Data.Vector       (Vector)
import GHC.Generics      (Generic)

import qualified Data.ByteString           as BS
import qualified Data.ByteString.Lazy      as LBS
import qualified Data.Text                 as T
import qualified Network.HTTP.Types.Method as Method

import GitHub.Data.Id   (Id, untagId)
import GitHub.Data.Name (Name, untagName)

------------------------------------------------------------------------------
-- Auxillary types
------------------------------------------------------------------------------

type Paths = [String]
type QueryString = [(BS.ByteString, Maybe BS.ByteString)]
type Count = Int

class IsPathPart a where
    toPathPart :: a -> String

instance IsPathPart (Name a) where
    toPathPart = T.unpack . untagName

instance IsPathPart (Id a) where
    toPathPart = show . untagId

-- | Http method of requests with body.
data CommandMethod a where
    Post   :: CommandMethod a
    Patch  :: CommandMethod a
    Put    :: CommandMethod a
    Delete :: CommandMethod ()
    deriving (Typeable)

deriving instance Eq (CommandMethod a)

instance Show (CommandMethod a) where
    showsPrec _ Post    = showString "Post"
    showsPrec _ Patch   = showString "Patch"
    showsPrec _ Put     = showString "Put"
    showsPrec _ Delete  = showString "Delete"

instance Hashable (CommandMethod a) where
    hashWithSalt salt Post    = hashWithSalt salt (0 :: Int)
    hashWithSalt salt Patch   = hashWithSalt salt (1 :: Int)
    hashWithSalt salt Put     = hashWithSalt salt (2 :: Int)
    hashWithSalt salt Delete  = hashWithSalt salt (3 :: Int)

toMethod :: CommandMethod a -> Method.Method
toMethod Post   = Method.methodPost
toMethod Patch  = Method.methodPatch
toMethod Put    = Method.methodPut
toMethod Delete = Method.methodDelete

-- | Result of merge operation
data MergeResult = MergeSuccessful
                 | MergeCannotPerform
                 | MergeConflict
    deriving (Eq, Ord, Read, Show, Enum, Bounded, Generic, Typeable)

instance Hashable MergeResult

-- | Status code transform
data StatusMap a where
    StatusOnlyOk :: StatusMap Bool
    StatusMerge  :: StatusMap MergeResult
    deriving (Typeable)

deriving instance Eq (StatusMap a)

instance Show (StatusMap a) where
    showsPrec _ StatusOnlyOk  = showString "StatusOnlyOK"
    showsPrec _ StatusMerge   = showString "StatusMerge"

instance Hashable (StatusMap a) where
    hashWithSalt salt StatusOnlyOk = hashWithSalt salt (0 :: Int)
    hashWithSalt salt StatusMerge  = hashWithSalt salt (1 :: Int)

------------------------------------------------------------------------------
-- Github request
------------------------------------------------------------------------------

-- | Github request data type.
--
-- * @k@ describes whether authentication is required. It's required for non-@GET@ requests.
-- * @a@ is the result type
--
-- /Note:/ 'Request' is not 'Functor' on purpose.
data Request (k :: Bool) a where
    Query        :: FromJSON a => Paths -> QueryString -> Request k a
    PagedQuery   :: FromJSON (Vector a) => Paths -> QueryString -> Maybe Count -> Request k (Vector a)
    Command      :: FromJSON a => CommandMethod a -> Paths -> LBS.ByteString -> Request 'True a
    StatusQuery  :: StatusMap a -> Request k () -> Request k a
#if __GLASGOW_HASKELL >= 708
    deriving (Typeable)
#endif

deriving instance Eq (Request k a)

instance Show (Request k a) where
    showsPrec d r =
        case r of
            Query ps qs -> showParen (d > appPrec) $
                showString "Query "
                    . showsPrec (appPrec + 1) ps
                    . showString " "
                    . showsPrec (appPrec + 1) qs
            PagedQuery ps qs l -> showParen (d > appPrec) $
                showString "PagedQuery "
                    . showsPrec (appPrec + 1) ps
                    . showString " "
                    . showsPrec (appPrec + 1) qs
                    . showString " "
                    . showsPrec (appPrec + 1) l
            Command m ps body -> showParen (d > appPrec) $
                showString "Command "
                    . showsPrec (appPrec + 1) m
                    . showString " "
                    . showsPrec (appPrec + 1) ps
                    . showString " "
                    . showsPrec (appPrec + 1) body
            StatusQuery m req -> showParen (d > appPrec) $
                showString "Status "
                    . showsPrec (appPrec + 1) m
                    . showString " "
                    . showsPrec (appPrec + 1) req
      where appPrec = 10 :: Int

instance Hashable (Request k a) where
    hashWithSalt salt (Query ps qs) =
        salt `hashWithSalt` (0 :: Int)
             `hashWithSalt` ps
             `hashWithSalt` qs
    hashWithSalt salt (PagedQuery ps qs l) =
        salt `hashWithSalt` (1 :: Int)
             `hashWithSalt` ps
             `hashWithSalt` qs
             `hashWithSalt` l
    hashWithSalt salt (Command m ps body) =
        salt `hashWithSalt` (2 :: Int)
             `hashWithSalt` m
             `hashWithSalt` ps
             `hashWithSalt` body
    hashWithSalt salt (StatusQuery sm req) =
        salt `hashWithSalt` (3 :: Int)
             `hashWithSalt` sm
             `hashWithSalt` req
