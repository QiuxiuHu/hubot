# Description
#   Trys to crash Hubot on purpose
#
# Commands:
#   hubot boom - try to crash Hubot
#   hubot boom emit with msg - try to crash Hubot by emitting an error with a msg
#   hubot boom emit without msg - try to crash Hubot by emitting an error without a msg
#   hubot boom throw- try to crash Hubot with a throw
#

boomError = (boom, string) ->
  new Error "Trying to #{boom} because you told me to #{string}"

module.exports = (robot) ->
  robot.respond /(boo+m)(?: (emit with(?:out)? msg|timeout|throw))?/i, (msg) ->
    boom = msg.match[1]
    how = msg.match[2]
    err = boomError(how)

    switch msg.match[1]
      when 'emit with msg'
        robot.emit 'error', boomError(how), msg
      when 'emit without msg'
        robot.emit 'error', boomError(how)
      when 'timeout'
        setTimeout (->
          throw boomError(how)
        ), 0
      else
        throw boomError(how)
