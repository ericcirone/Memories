# Memories
An iOS app that displays photos from your photo library taken on a particular day in history. Memories is a fully featured app including a Today View extension, a way for the user to Rate the app or contact the developer from the settings screen, and an In-App purchase to unlock certain features.

http://memories.land/

Memories uses icon images from the [Essence](http://iconsandcoffee.com/essence/) collection by [Icons & Coffee](http://iconsandcoffee.com), who hold the copyright to the images. They are provided in this repo with permission from Icons & Coffee.

# Downloading the code
Clone the repo: `git clone https://github.com/mluisbrown/Memories.git`

You will need [Xcode 9.0](https://developer.apple.com/xcode/download/) to build the app as it is entirely written in [Swift 4.0](https://swift.org). The project uses [Carthage](https://github.com/Carthage/Carthage) as a dependency manager, so you will need that too.

One you have installed Carthage run `carthage update` in the project root (where the `Cartfile` is). This will download and build the dependencies into the `Carthage` directory.

# Getting started
Open `Memories.xcodeproj` in Xcode. Build and run! The iOS simulator only has a handful of photos pre-installed. If you want to test with more photos from different dates you can add photos the the simulator's photo library by just dragging and dropping them into the simulator window.

# Contributing
This project is a fully featured app developed by myself (Michael Brown) and available in the Apple iOS App Store, and includes a freemium business model by the way of restricted features that are unlocked through an In-App purchase. As such I don't expect to receive a significant number of community contributions. I've opted to develop this project in the open from now on partly as an experiment and partly to give more visibility to the work I do on [evenings and weekends](http://www.theonion.com/blogpost/find-the-thing-youre-most-passionate-about-then-do-31742).

However, don't hesitate to send me a pull request if there's something you think needs improving. 
