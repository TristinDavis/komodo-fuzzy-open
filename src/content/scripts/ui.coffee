this.extensions           = {} unless extensions?
this.extensions.fuzzyopen = {} unless extensions.fuzzyopen?

`const Cc = Components.classes`
`const Ci = Components.interfaces`

`const HTML_NS = 'http://www.w3.org/1999/xhtml'`

$element = (id) -> document.getElementById id
$on      = (element, event, block) -> element.addEventListener event, block, if event.indexOf('key') is 0 then true else false
$sleep   = (interval, resume) -> setTimeout resume, interval
$new     = (tagName, attrs) ->
  element = document.createElementNS HTML_NS, tagName
  (element[key] = value) for key, value of attrs if attrs
  element
$stop    = (event) ->
  event.stopPropagation()
  event.preventDefault()

strings = Cc['@mozilla.org/intl/stringbundle;1'].getService(Ci.nsIStringBundleService).createBundle 'chrome://fuzzyopen/locale/fuzzyopen.properties'


this.extensions.fuzzyopen.ui = class UI

  @top:     null
  @history: []

  constructor: (queryId, resultsId, workingId, hideList) ->
    return new UI arguments... if this not instanceof UI
    @queryElement   = $element queryId
    @resultsElement = $element resultsId
    @workingElement = $element workingId
    @hideElements   = if hideList then $element id for id in hideList else []
    @path           = null
    @fuzzyOpen      = extensions.fuzzyopen.FuzzyOpen()
    UI.top          = this unless UI.top
    @addEvents()

  addEvents: ->

    $on @queryElement, 'command', =>
      value = @queryElement.value.trim()
      if value.length
        @open value
      else
        @hide()

    getList = => if (list = @resultsElement.childNodes[0])?.id is 'fuzzyopen-list' then list else null
    move    = (direction) =>
      return unless list = getList()
      prev = list.querySelector '.selected'
      next = (if direction is 'up' then prev.previousSibling else prev.nextSibling) if prev
      next = (if direction is 'up' then list.childNodes[list.childNodes.length - 1] else list.childNodes[0]) if not next
      return if next is prev
      prev.className  = '' if prev
      next.className  = 'selected'
      visibleTop      = @resultsElement.scrollTop
      nextTop         = next.offsetTop - list.offsetTop
      visibleBottom   = visibleTop + @resultsElement.boxObject.height
      nextBottom      = nextTop + next.offsetHeight
      @resultsElement.scrollTop  = nextTop                    if nextTop < visibleTop
      @resultsElement.scrollTop += nextBottom - visibleBottom if nextBottom > visibleBottom

    $on @queryElement, 'keypress', (event) =>
      key       = event.keyCode
      if key in [KeyEvent.DOM_VK_ENTER, KeyEvent.DOM_VK_RETURN]
        $stop event
        return unless list = getList()
        selected = list.querySelector '.selected'
        return unless selected
        ko.open.URI selected.getAttribute 'data-uri'
        @pushHistory()
        UI.toggleLeftPane() if this is UI.top
      else if key is KeyEvent.DOM_VK_UP
        $stop event
        if @queryElement.value.length < 1 and UI.history.length
          @queryElement.value = UI.history[UI.history.length - 1]
          @open @queryElement.value
        else
          move 'up'
      else if key is KeyEvent.DOM_VK_DOWN
        $stop event
        move 'down'
      else if '1' <= (character = String.fromCharCode event.charCode) <= '9' and (event.metaKey or event.ctrlKey)
        $stop event
        return unless list = getList()
        prev = list.querySelector '.selected'
        next = list.querySelectorAll('li')[character - '1']
        prev.className  = '' if prev
        return unless next
        next.className  = 'selected'
        ko.open.URI next.getAttribute 'data-uri'
        @pushHistory()
        UI.toggleLeftPane() if this is UI.top

    $on @fuzzyOpen, 'loading', =>
      @empty()
      loading = $new 'div', className: 'loading'
      loading.innerHTML = "<p><span>#{ strings.GetStringFromName 'loading' }</span></p>"
      @resultsElement.appendChild loading

    $on @fuzzyOpen, 'working', =>
      @isWorking yes
      @empty()

  update: (places) ->
    @hide()
    @path = places.manager.currentPlace
    if @path and places.manager.currentPlaceIsLocal
      @queryElement.removeAttribute 'disabled'
    else
      @queryElement.setAttribute 'disabled', 'true'

  open: (value) ->
    @toggle yes
    @isWorking no
    @fuzzyOpen.stop()
    @fuzzyOpen.find value, @path, (error, result) =>
      @isWorking no
      @empty()
      return @displayError error if error
      @displayResult result

  hide: ->
    @fuzzyOpen.stop()
    @queryElement.value = ''
    @toggle no
    @isWorking no
    @empty()

  toggle: (visible) ->
    @resultsElement.setAttribute 'collapsed', not visible
    element.setAttribute 'collapsed', visible for element in @hideElements

  isWorking: (flag) ->
    className = 'fuzzyopen-working'
    if flag
      @workingElement.className = "#{ @workingElement.className or '' } #{className}".trimLeft()
    else
      @workingElement.className = (@workingElement.className or '').replace ///\s*#{className}\b///, ''

  empty: ->
    @resultsElement.removeChild first while first = @resultsElement.childNodes[0]

  displayError: (error) ->
    message = $new 'div', className: 'exception'
    message.innerHTML = "<h2><span>#{ strings.GetStringFromName 'uncaughtError' }</span></h2><pre><code></code></pre>"
    message.getElementsByTagName('code')[0].appendChild document.createTextNode "#{error.message}, #{error.filename}:#{error.lineno}"
    @resultsElement.appendChild message

  displayEmpty: ->
    message = $new 'div', className: 'warning'
    message.innerHTML = "<p><span>#{ strings.GetStringFromName 'noResults' }</span></p>"
    @resultsElement.appendChild message

  displayResult: (files) ->
    return @displayEmpty() unless files.length
    open      = '{{'
    close     = '}}'
    escape    = (string) ->
      string.replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(open, '<em>', 'g')
            .replace(close, '</em>', 'g')
    normalize = (string) ->
      list   = if string instanceof Array then string else [string]
      result = []
      while value = list.shift()
        value = open + value if level > 0
        level = 0
        for i from 0 to (value.length - if level > 0 then close.length + 1 else 1)
          remaining = value.substring i
          if remaining.indexOf(open) is 0
            level++
          else if remaining.indexOf(close) is 0
            level--
        value = open + value  if level < 0
        value = value + close if level > 0
        result.push value
      if string instanceof Array then result else result.join ''
    list = $new 'ol', id: 'fuzzyopen-list'
    html = ''
    for file, i in files
      path = file.file
      for j from file.groups.length - 1 to 0 by -1
        path = "#{ path.substring 0, file.groups[j][0] }#{open}#{ path.substring file.groups[j][0], file.groups[j][1] }#{close}#{ path.substring file.groups[j][1], path.length }"
      extension = if path.indexOf('.') < 0 then '•' else path.split('.').pop()
      dirName   = (part for part in path.split('/') when part.length)
      baseName  = dirName.pop()
      html += """
      <li#{ if i is 0 then ' class=" selected"' else '' } data-uri="#{ escape "#{@path}/#{file.file}" }">
        <div class="extension"><strong><img src="moz-icon://.#{ encodeURIComponent extension or 'txt' }?size=16" />#{ escape normalize extension }</strong></div>
        <div class="file">
          <div class="name"><span class="icon" />#{ escape normalize baseName }</div>
          <div class="path"><span class="directory">#{ (escape part for part in normalize(part for part in dirName)).join '</span><span class="separator">→<wbr /></span><span class="directory">' }</span></div>
        </div>
      </li>
      """
    list.innerHTML = html
    $on list, 'click', (event) =>
      parent = event.target
      while parent and parent isnt list
        uri = parent.getAttribute 'data-uri'
        if uri
          list.querySelector('.selected').className = ''
          ko.open.URI uri
          parent.className = 'selected'
          break
        parent = parent.parentNode
    @resultsElement.appendChild list

  pushHistory: ->
    value = @queryElement.value.trim()
    UI.history.splice i, 1 for stored, i in UI.history when stored is value
    UI.history.push value

  @toggleLeftPane: (event) ->
    ko.commands.doCommandAsync command = 'cmd_viewLeftPane', event
    $sleep 125, =>
      element = $element command
      return unless element
      box     = $element element.getAttribute 'box'
      return unless box
      if box.getAttribute('collapsed') is 'true'
        UI.top.hide()
      else
        if UI.top.queryElement.value.length
          UI.top.hide()
        UI.top.queryElement.focus()
