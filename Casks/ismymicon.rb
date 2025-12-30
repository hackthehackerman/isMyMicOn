cask "ismymicon" do
  version "0.1.0"
  sha256 "531abf9d6392313da07dd4448bbc09c6d39e90fafd8def37efefd31b3441e081"

  url "https://github.com/hackthehackerman/isMyMicOn/releases/download/v#{version}/IsMyMicOn.zip"
  name "IsMyMicOn"
  desc "Menu bar utility for quick audio input/output switching"
  homepage "https://github.com/hackthehackerman/isMyMicOn"

  app "IsMyMicOn.app"
end
