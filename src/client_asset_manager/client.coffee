# Single-page Client
# ------------------
# Allows you to define which assets should be served for each client
# TODO: Cleanup this code. It's way too messy for my liking

log = console.log
fs = require('fs')
pathlib = require('path')
magicPath = require('./magic_path')

templateEngine = require('./template_engine').init(root)

exports.init = (root, codeWrappers) ->

  containerDir = '/client/static/assets'
  templateDir = 'client/templates'

  class Client

    constructor: (@name, @paths) ->
      @id = Number(Date.now())
      @name = name

    # Generate JS/CSS Script/Link tags for inclusion in the client's HTML
    headers: (packAssets = false) ->
      ts = @id
      headers = []

      if packAssets
        headers.push tag.css("/assets/#{@name}/#{@id}.css")
        headers.push tag.js("/assets/#{@name}/#{@id}.js")
      else
        @paths.css?.forEach (path) ->
          magicPath.files(root + '/client/css', path).forEach (file) ->
            headers.push tag.css("/_dev/css?#{file}&ts=#{ts}")

        # SocketStream Browser Client
        headers.push tag.js("/_dev/client?ts=#{ts}")

        @paths.code?.forEach (path) ->
          magicPath.files(root + '/client/code', path).forEach (file) ->
            headers.push tag.js("/_dev/code?#{file}&ts=#{ts}")

      # Output list of headers
      headers

    # Attempts to serve a cached copy of the HTML for this client if it exists, or generates it live if not
    htmlFromCache: (ssClient, formatters, packAssets, cb) ->
      if packAssets
        fileName = containerDir + '/' + @name + '/' + @id + '.html'
        fs.readFile root + fileName, 'utf8', (err, output) ->
          cb output
      else
        @html(ssClient, formatters, false, cb)

    # Generate contents of the main HTML view
    html: (ssClient, formatters, packAssets, cb) ->
      includes = []
      paths = @paths

      outputView = ->
        view = paths.view
        sp = view.split('.')
        extension = sp[sp.length-1]
        path = "#{root}/client/views/#{view}"

        formatter = formatters[extension]
        throw new Error("Unable to output view. Unsupported file extension #{extension}. Please provide a suitable formatter") unless formatter
        throw new Error("Unable to render view. #{formatter.name} is not a HTML formatter") unless formatter.assetType == 'html'

        formatter.compile(path, {headers: includes.join(''), filename: path}, cb)
      
      if ssClient.html?
        
        ssClient.html (codeForView) =>

          includes.push(codeForView)

          # Add links to CSS and JS files
          includes = includes.concat(@headers(packAssets))

          # Add any Client-side Templates
          if paths.tmpl?
            files = magicPath.files(root + '/' + templateDir, paths.tmpl)
            templateEngine.generate root, templateDir, files, formatters, (templateHTML) ->
              includes.push templateHTML
              outputView()
          else
            outputView()
  
    pack: (ssClient, formatters) ->

      asset = require('./asset').init(root, formatters, codeWrappers)

      packAssetSet = (assetType, paths, dir, concatinator, initialCode = '') ->

        processFiles = (fileContents = [], i = 0) ->
          path = filePaths[i]

          asset[assetType] path, {compress: true}, (output) ->
            fileContents.push(output)

            if filePaths[i+1]
              processFiles(fileContents, i+1)
            else
              # This is the final file - output contents
              output = fileContents.join(concatinator)
              output = initialCode + output
              file = clientDir + '/' + id + '.' + assetType

              fs.writeFileSync(root + file, output)
              log('✓'.green, 'Packed ' + filePaths.length + ' files into ' + file)

        # Expand any dirs into real files
        if paths && paths.length > 0
          filePaths = []
          prefix = root + '/' + dir
          paths.forEach (path) ->
            magicPath.files(prefix, path).forEach (file) -> filePaths.push(file)
          processFiles()


      id = @id
      clientDir = containerDir + '/' + @name

      log "Pre-packing and minifying the '#{@name}' client...".yellow

      # Create directory for this client
      fs.mkdirSync(root + containerDir) unless pathlib.existsSync(root + containerDir)
      fs.mkdirSync(root + clientDir) unless pathlib.existsSync(root + clientDir)
   
      # Output CSS
      packAssetSet('css', @paths.css, 'client/css', "\n")

      # Output JS
      ssClient.code (output) =>
        packAssetSet('js', @paths.code, 'client/code', "; ", output)

      # Output HTML view
      @html ssClient, formatters, true, (output) ->
        file = clientDir + '/' + id + '.html'
        fs.writeFileSync(root + file, output)
        log('✓'.green, 'Created and cached HTML file ' + file)



# Private

# Helpers to generate HTML tags
tag =

  css: (path) ->
    '<link href="' + path + '" media="screen" rel="stylesheet" type="text/css">'

  js: (path) ->
    '<script src="' + path + '" type="text/javascript"></script>'
