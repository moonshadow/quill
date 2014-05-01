_             = require('lodash')
_.str         = require('underscore.string')
pkg           = require('../package.json')
EventEmitter2 = require('eventemitter2').EventEmitter2
Editor        = require('./editor')
Format        = require('./format')
Range         = require('./lib/range')
Tandem        = require('tandem-core')

Modules =
  Authorship    : require('./modules/authorship')
  ImageTooltip  : require('./modules/image-tooltip')
  Keyboard      : require('./modules/keyboard')
  LinkTooltip   : require('./modules/link-tooltip')
  MultiCursor   : require('./modules/multi-cursor')
  PasteManager  : require('./modules/paste-manager')
  Toolbar       : require('./modules/toolbar')
  UndoManager   : require('./modules/undo-manager')

Themes =
  Default : require('./themes/default')
  Snow    : require('./themes/snow')


class Quill extends EventEmitter2
  @version: pkg.version
  @editors: []

  @Module: Modules
  @Theme: Themes

  @DEFAULTS:
    formats: ['align', 'bold', 'italic', 'strike', 'underline', 'color', 'background', 'font', 'size', 'link', 'image']
    modules:
      'keyboard': true
      'paste-manager': true
      'undo-manager': true
    pollInterval: 100
    readOnly: false
    theme: 'default'

  @events:
    MODULE_INIT      : 'module-init'
    POST_EVENT       : 'post-event'
    PRE_EVENT        : 'pre-event'
    RENDER_UPDATE    : 'renderer-update'
    SELECTION_CHANGE : 'selection-change'
    TEXT_CHANGE      : 'text-change'

  @sources:
    API    : 'api'
    SILENT : 'silent'
    USER   : 'user'

  constructor: (container, options = {}) ->
    container = document.querySelector(container) if _.isString(container)
    throw new Error('Invalid Quill container') unless container?
    moduleOptions = _.defaults(options.modules or {}, Quill.DEFAULTS.modules)
    html = container.innerHTML
    @options = _.defaults(options, Quill.DEFAULTS)
    @options.modules = moduleOptions
    @options.id = @id = "quill-#{Quill.editors.length + 1}"
    @options.emitter = this
    @modules = {}
    @editor = new Editor(container, this, @options)
    @root = @editor.doc.root
    Quill.editors.push(this)
    this.setHTML(html, Quill.sources.SILENT)
    themeClass = _.str.capitalize(_.str.camelize(@options.theme))
    @theme = new Quill.Theme[themeClass](this, @options)
    _.each(@options.modules, (option, name) =>
      this.addModule(name, option)
    )

  addContainer: (className, before = false) ->
    @editor.renderer.addContainer(className, before)

  addFormat: (name, format) ->
    @editor.doc.addFormat(name, format)

  addModule: (name, options) ->
    className = _.str.capitalize(_.str.camelize(name))
    moduleClass = Quill.Module[className]
    throw new Error("Cannot load #{name} module. Are you sure you included it?") unless moduleClass?
    options = {} unless _.isObject(options)  # Allow for addModule('module', true)
    options = _.defaults(options, @theme.constructor.OPTIONS[name] or {}, moduleClass.DEFAULTS or {})
    @modules[name] = new moduleClass(this, @root, options)
    this.emit(Quill.events.MODULE_INIT, name, @modules[name])
    return @modules[name]

  addStyles: (styles) ->
    @editor.renderer.addStyles(styles)

  deleteText: (index, length, source = Quill.sources.API) ->
    [index, length, formats, source] = this._buildParams(index, length, {}, source)
    return unless length > 0
    delta = Tandem.Delta.makeDeleteDelta(this.getLength(), index, length)
    @editor.applyDelta(delta, source)

  emit: (eventName, args...) ->
    super(Quill.events.PRE_EVENT, eventName, args...)
    super(eventName, args...)
    super(Quill.events.POST_EVENT, eventName, args...)

  focus: ->
    @root.focus()

  formatText: (index, length, name, value, source) ->
    [index, length, formats, source] = this._buildParams(index, length, name, value, source)
    return unless length > 0
    formats = _.reduce(formats, (formats, value, name) =>
      format = @editor.doc.formats[name]
      # TODO warn if no format
      formats[name] = null unless value and value != format.config.default     # false will be composed and kept in attributes
      return formats
    , formats)
    delta = Tandem.Delta.makeRetainDelta(this.getLength(), index, length, formats)
    @editor.applyDelta(delta, source)

  getContents: (index = 0, length = null) ->
    if _.isObject(index)
      length = index.end - index.start
      index = index.start
    else
      length = this.getLength() - index unless length?
    ops = @editor.getDelta().getOpsAt(index, length)
    return new Tandem.Delta(0, ops)

  getHTML: ->
    return @root.innerHTML

  getLength: ->
    return @editor.getDelta().endLength

  getModule: (name) ->
    return @modules[name]

  getSelection: ->
    @editor.checkUpdate()   # Make sure we access getRange with editor in consistent state
    return @editor.selection.getRange()

  getText: (index, length) ->
    return _.pluck(this.getContents(index, length).ops, 'value').join('')

  insertEmbed: (index, type, url, source) ->
    this.insertText(index, Format.EMBED_TEXT, type, url, source)

  insertText: (index, text, name, value, source) ->
    [index, length, formats, source] = this._buildParams(index, 0, name, value, source)
    return unless text.length > 0
    delta = Tandem.Delta.makeInsertDelta(this.getLength(), index, text, formats)
    @editor.applyDelta(delta, source)

  onModuleLoad: (name, callback) ->
    if (@modules[name]) then return callback(@modules[name])
    this.on(Quill.events.MODULE_INIT, (moduleName, module) ->
      callback(module) if moduleName == name
    )

  prepareFormat: (name, value) ->
    format = @editor.doc.formats[name]
    return unless format?     # TODO warn
    format.prepare(value)

  setContents: (delta, source = Quill.sources.API) ->
    if _.isArray(delta)
      delta = Tandem.Delta.makeDelta({
        startLength: this.getLength()
        ops: delta
      })
    else
      delta = Tandem.Delta.makeDelta(delta)
      delta.startLength = this.getLength()
    @editor.applyDelta(delta, source)

  setHTML: (html, source = Quill.sources.API) ->
    @editor.doc.setHTML(html)
    @editor.checkUpdate(source)

  setSelection: (start, end, source = Quill.sources.API) ->
    if _.isNumber(start) and _.isNumber(end)
      range = new Range(start, end)
    else
      range = start
      source = end or source
    @editor.selection.setRange(range, source)

  updateContents: (delta, source = Quill.sources.API) ->
    @editor.applyDelta(delta, source)

  # fn(Number index, Number length, String name, String value, String source)
  # fn(Number index, Number length, Object formats, String source)
  # fn(Object range, String name, String value, String source)
  # fn(Object range, Object formats, String source)
  _buildParams: (params...) ->
    if _.isObject(params[0])
      index = params[0].start
      length = params[0].end - index
      params.splice(0, 1, index, length)
    if _.isString(params[2])
      formats = {}
      formats[params[2]] = params[3]
      params.splice(2, 2, formats)
    params[3] ?= Quill.sources.API
    return params


module.exports = Quill
