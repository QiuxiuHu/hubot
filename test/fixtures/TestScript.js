'use strict'

// Description: A test script for the robot to load
//
// Commands:
//   hubot test - Responds with a test response
//
module.exports = robot => {
  robot.hasLoadedTestJsScript = true
  robot.respond('test', async res => {
    await res.send('test response')
  })
}
