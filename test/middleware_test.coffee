# Assertions and Stubbing
chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'

{ expect } = chai

mockery = require 'mockery'

# Hubot classes
Robot = require '../src/robot.coffee'
{ CatchAllMessage, EnterMessage, TextMessage } = require '../src/message'
Adapter = require '../src/adapter'
Response = require '../src/response'
Middleware = require '../src/middleware'

# Preload the Hubot mock adapter but substitute in the latest version of Adapter
mockery.enable()
mockery.registerAllowable 'hubot-mock-adapter'
mockery.registerAllowable 'lodash' # hubot-mock-adapter uses lodash
# Force hubot-mock-adapter to use the latest version of Adapter
mockery.registerMock 'hubot/src/adapter', Adapter
# Load the mock adapter into the cache
require 'hubot-mock-adapter'
# We're done with mockery
mockery.deregisterMock 'hubot/src/adapter'
mockery.disable()


describe 'Middleware', ->
  describe 'Unit Tests', ->
    beforeEach ->
      @robot =
        # Stub out event emitting
        emit: sinon.spy()

      @middleware = new Middleware(@robot)

    describe '#execute', ->
      it 'executes synchronous middleware', (testDone) ->
        testMiddleware = sinon.spy (robot, context, next, done) =>
          next(done)

        @middleware.register testMiddleware

        middlewareFinished = ->
          expect(testMiddleware).to.have.been.called
          testDone()

        @middleware.execute(
          {}
          (_, done) -> done()
          middlewareFinished
        )

      it 'executes asynchronous middleware', (testDone) ->
        testMiddleware = sinon.spy (robot, context, next, done) ->
          # Yield to the event loop
          process.nextTick ->
            next(done)

        @middleware.register testMiddleware

        middlewareFinished = (context, done) ->
          expect(testMiddleware).to.have.been.called
          testDone()

        @middleware.execute(
          {}
          (_, done) -> done()
          middlewareFinished
        )

      it 'passes the correct arguments to each middleware', (testDone) ->
        testContext = {}
        # Pull the Robot in scope for simpler callbacks
        testRobot = @robot

        testMiddleware = (robot, context, next, done) ->
          # Break out of middleware error handling so assertion errors are
          # more visible
          process.nextTick ->
            # Check that variables were passed correctly
            expect(robot).to.equal(testRobot)
            expect(context).to.equal(testContext)
            next(done)

        @middleware.register testMiddleware

        @middleware.execute(
          testContext
          (_, done) -> done()
          -> testDone()
        )

      it 'executes all registered middleware in definition order', (testDone) ->
        middlewareExecution = []

        testMiddlewareA = (robot, context, next, done) =>
          middlewareExecution.push('A')
          next(done)

        testMiddlewareB = (robot, context, next, done) ->
          middlewareExecution.push('B')
          next(done)

        @middleware.register testMiddlewareA
        @middleware.register testMiddlewareB

        middlewareFinished = ->
          expect(middlewareExecution).to.deep.equal(['A','B'])
          testDone()

        @middleware.execute(
          {}
          (_, done) -> done()
          middlewareFinished
        )

      it 'executes the next callback after the function returns when there is no middleware', (testDone) ->
        finished = false
        @middleware.execute(
          {}
          ->
            expect(finished).to.be.ok
            testDone()
          ->
        )
        finished = true

      it 'always executes middleware after the function returns', (testDone) ->
        finished = false

        @middleware.register (robot, context, next, done) ->
          expect(finished).to.be.ok
          testDone()

        @middleware.execute {}, (->), (->)
        finished = true

      it 'does the right thing with done callbacks', (testDone) ->
        # we want to ensure that the 'done' callbacks are nested correctly
        # (executed in reverse order of definition)
        execution = []

        testMiddlewareA = (robot, context, next, done) ->
          execution.push 'middlewareA'
          next () ->
            execution.push 'doneA'
            done()

        testMiddlewareB = (robot, context, next, done) ->
          execution.push 'middlewareB'
          next () ->
            execution.push 'doneB'
            done()

        @middleware.register testMiddlewareA
        @middleware.register testMiddlewareB

        allDone = () ->
          expect(execution).to.deep.equal(['middlewareA', 'middlewareB', 'doneB', 'doneA'])
          testDone()

        @middleware.execute(
          {}
          # Short circuit at the bottom of the middleware stack
          (_, done) -> done()
          allDone
        )

      describe 'error handling', ->
        it 'does not execute subsequent middleware after the error is thrown', (testDone) ->
          middlewareExecution = []

          testMiddlewareA = (robot, context, next, done) ->
            middlewareExecution.push('A')
            next(done)

          testMiddlewareB = (robot, context, next, done) ->
            middlewareExecution.push('B')
            throw new Error

          testMiddlewareC = (robot, context, next, done) ->
            middlewareExecution.push('C')
            next(done)

          @middleware.register testMiddlewareA
          @middleware.register testMiddlewareB
          @middleware.register testMiddlewareC

          middlewareFinished = sinon.spy()
          middlewareFailed = () =>
            expect(middlewareFinished).to.not.have.been.called
            expect(middlewareExecution).to.deep.equal(['A','B'])
            testDone()

          @middleware.execute(
            {}
            middlewareFinished
            middlewareFailed
          )

        it 'emits an error event', (testDone) ->
          testResponse = {}
          theError = new Error

          testMiddleware = (robot, context, next, done) ->
            throw theError

          @middleware.register testMiddleware

          @robot.emit = sinon.spy (name, err, response) ->
            expect(name).to.equal('error')
            expect(err).to.equal(theError)
            expect(response).to.equal(testResponse)

          middlewareFinished = sinon.spy()
          middlewareFailed = () =>
            expect(@robot.emit).to.have.been.called
            testDone()

          @middleware.execute(
            {response: testResponse},
            middlewareFinished,
            middlewareFailed
          )

        it 'unwinds the middleware stack (calling all done functions)', (testDone) ->
          extraDoneFunc = null

          testMiddlewareA = (robot, context, next, done) ->
            # Goal: make sure that the middleware stack is unwound correctly
            extraDoneFunc = sinon.spy () ->
              done()
            next extraDoneFunc

          testMiddlewareB = (robot, context, next, done) ->
            throw new Error

          @middleware.register testMiddlewareA
          @middleware.register testMiddlewareB

          middlewareFinished = sinon.spy()
          middlewareFailed = () ->
            # Sanity check that the error was actually thrown
            expect(middlewareFinished).to.not.have.been.called

            expect(extraDoneFunc).to.have.been.called
            testDone()

          @middleware.execute(
            {}
            middlewareFinished
            middlewareFailed
          )

    describe '#register', ->
      it 'adds to the list of middleware', ->
        testMiddleware = (robot, context, next, done) ->

        @middleware.register testMiddleware

        expect(@middleware.stack).to.include(testMiddleware)

      it 'validates the arity of middleware', ->
        testMiddleware = (robot, context, next, done, extra) ->

        expect(=> @middleware.register(testMiddleware)).to.throw(/Incorrect number of arguments/)

  # Per the documentation in docs/scripting.md
  # Any new fields that are exposed to middleware should be explicitly
  # tested for.
  describe 'Public API', ->
    beforeEach ->
      @robot = new Robot null, 'mock-adapter', yes, 'TestHubot'
      @robot.run

      # Re-throw AssertionErrors for clearer test failures
      @robot.on 'error', (name, err, response) ->
        if err?.constructor?.name == "AssertionError"
          process.nextTick () ->
            throw err

      @user = @robot.brain.userForId '1', {
        name: 'hubottester'
        room: '#mocha'
      }

      # Dummy middleware
      @middleware = sinon.spy (robot, listener, response, next, done) ->
        next(done)

      @robot.listenerMiddleware (robot, listener, response, next, done) =>
        @middleware.call @, robot, listener, response, next, done

      @testMessage = new TextMessage @user, 'message123'
      @robot.hear /^message123$/, (response) ->
      @testListener = @robot.listeners[0]

    afterEach ->
      @robot.server.close()
      @robot.shutdown()

    describe 'robot', ->
      it 'is the robot object', (testDone) ->
        @robot.receive @testMessage, () =>
          expect(@middleware).to.have.been.calledWithMatch(
            sinon.match.same(@robot) # robot
            sinon.match.any          # listener
            sinon.match.any          # response
            sinon.match.any          # next
            sinon.match.any          # done
          )
          testDone()

    describe 'listener', ->
      it 'is the listener object that matched', (testDone) ->
        @robot.receive @testMessage, () =>
          expect(@middleware).to.have.been.calledWithMatch(
            sinon.match.any                 # robot
            sinon.match.same(@testListener) # listener
            sinon.match.any                 # response
            sinon.match.any                 # next
            sinon.match.any                 # done
          )
          testDone()

      it 'has options.id (metadata)', (testDone) ->
        @robot.receive @testMessage, () =>
          expect(@middleware).to.have.been.calledWithMatch(
            sinon.match.any                    # robot
            sinon.match.has('options',
              sinon.match.has('id'))           # listener
            sinon.match.any                    # response
            sinon.match.any                    # next
            sinon.match.any                    # done
          )
          testDone()

    describe 'response', ->
      it 'is a Response that wraps the message', (testDone) ->
        @robot.receive @testMessage, () =>
          expect(@middleware).to.have.been.calledWithMatch(
            sinon.match.any                       # robot
            sinon.match.any                       # listener
            sinon.match.instanceOf(Response).and(
              sinon.match.has('message',
                sinon.match.same(@testMessage)))  # response
            sinon.match.any                       # next
            sinon.match.any                       # done
          )
          testDone()

    describe 'next', ->
      it 'is a function with arity one', (testDone) ->
        @robot.receive @testMessage, () =>
          expect(@middleware).to.have.been.calledWithMatch(
            sinon.match.any             # robot
            sinon.match.any             # listener
            sinon.match.any             # response
            sinon.match.func.and(
              sinon.match.has('length',
                sinon.match(1)))        # next
            sinon.match.any             # done
          )
          testDone()

    describe 'done', ->
      it 'is a function with arity zero', (testDone) ->
        @robot.receive @testMessage, () =>
          expect(@middleware).to.have.been.calledWithMatch(
            sinon.match.any             # robot
            sinon.match.any             # listener
            sinon.match.any             # response
            sinon.match.any             # next
            sinon.match.func.and(
              sinon.match.has('length',
                sinon.match(0)))        # done
          )
          testDone()
