# swift-fingerd


A basic implementation of a finger server writter with Swift.

This project's original purpose was to test specific usecases in a finger client. As such it's a bit rough and by no means
should be used in anything resembling a production environment.

It's not 100% complient with the RFC either. I'm sharing simply as something that will help others learn about the finger
protocol or basic TCP connection handling with Swift. I might improve it over time but it's a low priority. Though I'm
very happy to take in suggested changes if you want to contribute.

Further information on the finger spec: [Finger Protocol RFC](https://datatracker.ietf.org/doc/html/rfc1288)


## Building

1. Get packages `swift package update`
2. Build executable `swift build`
3. The exectuable is found in the `./build` directory

**Optional:**  You can run `swift package generate-xcodeproj` to create an xcode project file.


## Running

When built, you should end up with a `swift-fingerd` executable.

You can run `./swift-fingerd --help` for a full list of options

### Example using all parameters
`sudo ./swift-fingerd -h '0.0.0.0' -p 79 -v -d '~/my-user-dir'`

### Using example data

Some test users are provided in the project's `testusers` directory so you can run:

`sudo ./swift-fingerd -d '<project root>/testusers'`

then use finger like this:

`finger franklindstallone@localhost`

### Avoiding sudo

Port 79 is a privileged port so you'll likely need to use sudo, even if you run it as `swift run`, when
using the default port.

You can avoid that by running swift-fingerd like this:

`./swift-fingerd -d '~/<project root>/testusers/' --verbose -p 8081`

Then use `nc` to send the request:

`printf "franklindstallone\r\n" | nc localhost 8081`


## User data

You can reference the user data in the project's `testusers` directory.

Reading user data assumes you have:

1. A directory containing text files
2. The text files match the filename format `<username>.txt`
3. The contents within `<username>.txt` will be returned as the response.
4. A missing `<username>.txt` will return a user not found response.


## Dependencies

[Swift NIO](https://github.com/apple/swift-nio)

[Swift Argument Parser](https://github.com/apple/swift-argument-parser)
