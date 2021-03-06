{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE PatternSynonyms #-}
module Main where

import Control.Monad
import Foreign.C.Types
import SDL.Vect
import SDL (($=))
import qualified SDL
import Data.List (foldl')
import SDL.Raw.Timer as SDL hiding (delay)
import Text.Pretty.Simple

-- import Paths_simple-sdl-example(getDataFileName)

screenWidth, screenHeight :: CInt
(screenWidth, screenHeight) = (640, 480)

frameLimit :: Int
frameLimit = 60

-- This is our game world. It only consists of one lonely guy
-- who has a position and a velocity
data World
    = Guy
    { position :: Point V2 CDouble
    , velocity :: V2 CDouble
    } deriving (Show, Eq)

-- Our initial world starts out with the guy roughly in the middle
initialGuy :: World
initialGuy =
    Guy
    { position = P $ V2 (fromIntegral screenWidth / 2) (fromIntegral $ screenHeight - 100)
    , velocity = V2 0 0
    }

jumpVelocity :: V2 CDouble
jumpVelocity = V2 0 (-2)

walkingSpeed :: V2 CDouble
walkingSpeed = V2 1 0

gravity :: V2 CDouble
gravity = V2 0 0.7


-- These simplify matching on a specific key code
pattern KeyPressed a <- (SDL.KeyboardEvent (SDL.KeyboardEventData _ SDL.Pressed False (SDL.Keysym _ a _)))
pattern KeyReleased a <- (SDL.KeyboardEvent (SDL.KeyboardEventData _ SDL.Released _ (SDL.Keysym _ a _)))


-- This processed input and modifies velocities of things in our world accordingly
-- and then returns the new world
processInput :: World -> SDL.EventPayload -> World
processInput world@(Guy _ curVel) (KeyPressed SDL.KeycodeUp) =
    world { velocity = curVel * (V2 1 0) + jumpVelocity}
processInput world@(Guy _ curVel) (KeyPressed SDL.KeycodeLeft) =
    world { velocity = negate walkingSpeed + curVel  }
processInput world@(Guy _ curVel) (KeyPressed SDL.KeycodeRight) =
    world { velocity = walkingSpeed + curVel  }

processInput world@(Guy _ curVel) (KeyReleased SDL.KeycodeUp) =
    world { velocity = curVel - jumpVelocity }
processInput world@(Guy _ curVel) (KeyReleased SDL.KeycodeLeft) =
    world { velocity = curVel - negate walkingSpeed  }
processInput world@(Guy _ curVel) (KeyReleased SDL.KeycodeRight) =
    world { velocity = curVel - walkingSpeed  }
processInput w _ = w


-- This function takes cares of applying things like our entities' velocities
-- to their positions, as well as
updateWorld :: CDouble -> World -> World
updateWorld delta (Guy (P pos) vel) =
    let (V2 newPosX newPosY) = pos + (gravity + vel) * V2 delta delta
        -- Ensure that we stay within bounds
        fixedX = max 0 $ min newPosX (fromIntegral screenWidth - 50)
        fixedY = max 0 $ min (fromIntegral screenHeight - 100) newPosY
    in Guy (P $ V2 fixedX fixedY) vel


main :: IO ()
main = do

  -- Initialise SDL
  SDL.initialize [SDL.InitVideo]

  -- Create a window with the correct screensize and make it appear
  window <- SDL.createWindow "FirstGameHS"
    SDL.defaultWindow { SDL.windowInitialSize = V2 screenWidth screenHeight }
  SDL.showWindow window

  -- Create a renderer for the window for rendering textures
  renderer <-
    SDL.createRenderer
      window
      (-1)
      SDL.RendererConfig
        { SDL.rendererType = SDL.AcceleratedRenderer
        , SDL.rendererTargetTexture = False
        }

  SDL.rendererDrawColor renderer $= V4 maxBound maxBound maxBound maxBound

  -- Make a surface from file
  xOutSurface <- SDL.loadBMP "foo.bmp"
  texture <- SDL.createTextureFromSurface renderer xOutSurface

  -- Free the surface as we have a texture now
  SDL.freeSurface xOutSurface


  let loop last world = do
        events <- SDL.pollEvents

        -- Need to calculate the time delta
        now <- SDL.getPerformanceCounter
        freq <- SDL.getPerformanceFrequency

        let delta = (fromIntegral now - fromIntegral last) * 1000 / fromIntegral freq
            payloads = map SDL.eventPayload events
            quit = elem SDL.QuitEvent payloads

        -- Update functions
        let worldAfterInput = foldl' processInput world payloads
            newWorld        = updateWorld delta worldAfterInput

        SDL.clear renderer

        -- Render functions
        SDL.copy renderer texture Nothing Nothing
        -- Draw our world(guy) as a white rectangle
        let drawColor = SDL.rendererDrawColor renderer
        drawColor $= V4 255 255 255 0
        SDL.fillRect renderer . Just $ SDL.Rectangle (truncate <$> position newWorld) (V2 50 100)

        -- My attempt at an FPS limit. I don't write games so it is possible this is incorrect
        let frameDelay = 1000 / fromIntegral frameLimit
        when (delta < frameDelay) $ do
            SDL.delay (truncate $ frameDelay - delta)

        SDL.present renderer
        unless quit $ loop now newWorld

  now <- SDL.getPerformanceCounter
  loop now initialGuy

  SDL.destroyWindow window
  SDL.quit
