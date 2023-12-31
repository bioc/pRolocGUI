##' @rdname pRolocVis-apps
##' @param groupBy The feature meta-data label (\code{fData} column name)
##' to be used for summarising the features to be combined.
pRolocVis_aggregate <- function(object, 
                                fcol = "markers",
                                groupBy,
                                fig.height = "700px",
                                # legend.width = "200%",
                                # legend.cex = 1,
                                nchar = 25,
                                ...) {
  ## removed from arguments
  legend.width = "200%"
  legend.cex = 1
  mirrorX = FALSE
  mirrorY = FALSE
  all = TRUE
  fig.width = "100%"
  
  ## Return featureNames of proteins selected
  # on.exit(return(invisible(idDT)))

  ## Check input object is an MSnSet
  if (!inherits(object, "MSnSet"))
    stop("The input must be of class MSnSet")
  
  ## Check groubBy is specified
  if (missing(groupBy))
    stop("No groupBy specified")
  if (!groupBy %in% fvarLabels(object))
    stop("groupBy not found in fvarLabels")
  
  ## Rename object for convenience
  peps <- object
  
  ## Add a new column to fData with #features that have been combined
  n <- length(fvarLabels(peps))
  pglabel <- paste(groupBy, "(#feats)")
  tt <- table(fData(peps)[, groupBy])
  cc <- tt[fData(peps)[, groupBy]]
  cc <- paste0(names(cc), " (", cc,")")
  fData(peps)[, pglabel] <- cc
  fData(peps) <- fData(peps)[, c(n + 1, 1:n)] # Add pgLabel column so appears first in fData
  groupBy <- pglabel
  prots <- combineFeatures(peps, fData(peps)[, groupBy], 
                           cv = FALSE, ...)
  
  
  ## data for aggvar plot
  p0.max <- data.frame(MSnbase::aggvar(peps, groupBy, "max"))
  p0.max[, "nb_feats"] <- log10(p0.max[, "nb_feats"])
  p0.max <- p0.max[, c(2, 1)]
  p.max <- p0.max
  p.max[is.na(p.max)] <- 0  
  
  p0.mean <- data.frame(MSnbase::aggvar(peps, groupBy, "mean"))
  p0.mean[, "nb_feats"] <- log10(p0.mean[, "nb_feats"])
  p0.mean <- p0.mean[, c(2, 1)]
  p.mean <- p0.mean
  p.mean[is.na(p.mean)] <- 0  
  
  fData(peps)[, "aggvar_max"] <- p.max[fData(peps)[, groupBy], 2]
  fData(peps)[, "aggvar_mean"] <- p.mean[fData(peps)[, groupBy], 2]
  
  
  ## fcol checks
  # if (!is.null(fcol) && !fcol %in% fvarLabels(object)) {
  #   warning("No fcol found using fcol = NULL", immediate. = TRUE)
  #   fcol <- NULL
  # }
  # if (is.null(fcol)) {
  #   setUnknowncol("#000000")
  #   fcol <- "nullmarkers"
  #   m <- matrix(0, ncol = 1, nrow = nrow(object))
  #   rownames(m) <- featureNames(object)
  #   colnames(m) <- "0"
  #   fData(object)[, fcol] <- m
  # }

  ## Make any columns in the fData that are a matrix a vector 
  ## (we need to do this to make sure the table is displayed properly)
  peps <- .convertMatsToCols(peps)
  prots <- .convertMatsToCols(prots)
  
  
  ## Extract binary matrix (pmarkers) for the peptide MSnSet for markers
  if (isMrkVec(peps, fcol)) {
    ## Make a mrk vec mat, then extract mat
    mName <- paste0("Markers", format(Sys.time(), "%a%b%d%H%M%S%Y"))
    tmpObj <- mrkVecToMat(peps, fcol, mfcol = mName)
    pmarkers <- fData(tmpObj)[, mName]
  } else {
    pmarkers <- fData(peps)[, fcol]
  }
  
  
  ## Marker colours
  cols <- appStockcol()
  if (length(cols) < max(ncol(pmarkers))) {
    message("Too many features for available colours. Some colours will be duplicated.")
    n <- ncol(pmarkers / length(cols))
    cols <- rep(cols, n + 1)
  }
  myclasses <- colnames(pmarkers)
  cols <- cols[1:length(myclasses)]
  names(cols) <- myclasses

  
  # Shorten markers names if too long
  cn <- sapply(colnames(pmarkers),
               function(x) {
                 if (nchar(x) > nchar) {
                   x <- strsplit(x, "")[[1]]
                   x <- paste(x[1:nchar], collapse = "")
                   x <- sub(" +$", "", x)
                   x <- paste0(x, "...")
                 }
                 return(x)
               })
  names(cn) <- NULL
  colnames(pmarkers) <- cn
  
  
  ## Display all classes unless user specifies not to
  pmsel <- TRUE
  if (!all | ncol(pmarkers) > 15)
    pmsel <- 1  
  
  
  ## Get data for profiles 
  profs <- exprs(peps)
  
  ## Remap protein coords onto peptide PCA coords
  remapped <- remap(object = MSnSetList(list(peps, prots)))

  
  ## Get PCs for each plot 
  pcas <- list(plot2D(remapped[[2]], fcol = NULL, plot = FALSE,
                      mirrorX = FALSE, mirrorY = FALSE,
                      method = "none"),
               plot2D(remapped[[1]], fcol = NULL, plot = FALSE,
                      mirrorX = mirrorX, mirrorY = mirrorY,
                      method = "none"))
  

  ## Define data columns to be displayed on startup
  origFvarLab <- fvarLabels(peps)
  if (length(origFvarLab) > 6) {
    .ind <- which(origFvarLab == fcol)
    .gp <- which(origFvarLab == groupBy)
    .fvarL <- origFvarLab[-c(.ind, .gp)]
    ll <- c(.fvarL[1:3],"aggvar_max", "aggvar_mean") 
    selDT <- c(groupBy, ll, fcol)
  } else {
    selDT <- origFvarLab[1:length(origFvarLab)]
  }
 
  
  ## Create column of unknowns (needed later for plot2D in server)
  newName <- paste0(format(Sys.time(), "%a%b%d%H%M%S%Y"), "unknowns")
  fData(peps)[, newName] <- "unknown"
  fData(prots)[, newName] <- "unknown"
  
  
  ## all features are displayed on start
  # toSel_prot <- 1:nrow(prots)
  toSel <- 1:nrow(peps)
  feats_prot <- featureNames(prots)
  feats_pep <- featureNames(peps)
  idDT <- character()

  
  ## Build shiny app
  ui <- fluidPage(
    sidebarLayout(
      sidebarPanel(
        selectizeInput("markers", "Labels",
                       choices = myclasses,
                       multiple = TRUE,
                       selected = myclasses[pmsel]),
        sliderInput("trans", "Transparancy",
                    min = 0,  max = 1, value = 0.15),
        checkboxInput("checkbox", label = "Show labels", value = TRUE),
        br(),
        selectInput("aggvarDist", "Distance metric:", 
                    choices = c ("max", "mean")),
        br(),
        actionButton("clear", "Clear selection"),
        br(),
        width = 2),
      mainPanel(
        tabsetPanel(type = "tabs",
                    tabPanel("PCA", id = "pcaPanel",
                             fluidRow(
                               column(5, 
                                      plotOutput("scatter",
                                                 height = fig.height,
                                                 width = fig.width,
                                                 dblclick = "dblClickScatter"
                                                 ),
                                      offset = 0),
                               column(5, 
                                      plotOutput("pca",
                                                 height = fig.height,
                                                 width = fig.width,
                                                 dblclick = "dblClickPCA"
                                                 ),
                                      offset = 0),
                               column(2, 
                                      plotOutput("legend1",
                                                 height = fig.height,
                                                 width = legend.width))
                             )
                    ),
                    tabPanel("Profiles", id = "profilesPanel",
                             fluidRow(
                               column(8,
                                      plotOutput("profile2",
                                                 height = "400px",
                                                 width = "110%"),
                                      offset = 0),
                               
                               column(3, 
                                      plotOutput("legend2",
                                                 width = "100%"),
                                      offset = 0)
                             )
                    ),
                    tabPanel("Table Selection", id = "tableSelPanel",
                             fluidRow(
                               column(4,
                                      checkboxGroupInput("selTab", 
                                                         "Data columns to display",
                                                         choices = origFvarLab,
                                                         selected = selDT)
                               )
                             )
                    ),
                    ## feature data table is always visible
                    fluidRow(
                      column(12,
                             column(length(selDT),
                                    DT::dataTableOutput("fDataTable"))))
        )
      )
    ))
  
  
  
  server <-
    function(input, output, session) {
      
      ranges <- reactiveValues(x = c(min(pcas[[2]][, 1]), max(pcas[[2]][, 1])),
                               y = c(min(pcas[[2]][, 2]), max(pcas[[2]][, 2])))
      
      
      ## Reset/clear labels on plots
      resetLabels <- reactiveValues(logical = FALSE)
    
      
      ## Update data for aggvar plot
      protscatter0 <- reactive({
        if (resetLabels$logical) idDT <<- character()
        if (input$aggvarDist == "max") p0 <- p0.max
        if (input$aggvarDist == "mean") p0 <- p0.mean
        p0
      })
        
      protscatter <- reactive({
        if (resetLabels$logical) idDT <<- character()
        if (input$aggvarDist == "max") p <- p.max
        if (input$aggvarDist == "mean") p <- p.mean
        p
      })
      
      
      ## Get coords for proteins according to selectized marker class(es)
      mrkSel <- reactive({
        ind <- match(input$markers, colnames(pmarkers))
        .mrkSel <- vector("list", length(input$markers))
        for (i in seq(length(input$markers))) {
          if (is.na(ind[i])) {
            .mrkSel[[i]] <- NA
          } else {
            .mrkSel[[i]] <- which(pmarkers[, ind[i]] == 1)
          }
        }
        .mrkSel
      })
      
      
      ## Update colour transparacy according to slider input
      myCols <- reactive({
        scales::alpha(cols,
                      input$trans)[sapply(input$markers, function(z) 
                        which(names(cols) == z))]})
      

      ## Scatter plot
      output$scatter <- renderPlot({
        agg_dist <- nb_feats <- NULL ## to address no visible binding for global var note
        idDT <<- feats_pep[input$fDataTable_rows_selected]
        if (resetLabels$logical) idDT <<- character()
        ggscatter <- ggplot(data = protscatter(), 
                            aes(x = nb_feats, y = agg_dist)) +
          geom_point(alpha = .5) +
          xlab("log10(number of feats)") +
          geom_smooth(data = protscatter0(), 
                      mapping = aes(x = nb_feats, y = agg_dist), 
                      method = "lm", na.rm = TRUE)   ## add lineaer model
                                                     ## add na.rm to catch warning
        if (length(idDT) > 0) {
          highlight <- unique(fData(peps)[idDT, groupBy])
          ggscatter <- ggscatter + geom_point(data = protscatter()[highlight, ], 
                                              colour = "red")
          if (input$checkbox) {
            ggscatter <- ggscatter + annotate("text", x = protscatter()[highlight, 1], 
                                              y = protscatter()[highlight, 2] + .03, 
                                              label = highlight, colour = "red", 
                                              fontface = 2)
          }
        }
        ggscatter
      })
      
      
      ## PCA plot
      output$pca <- renderPlot({
        par(mar = c(4, 4, 0, 0))
        par(oma = c(1, 0, 0, 0))
        plot2D(peps, pch = 21, cex = 1,
               col = rep(getUnknowncol(), nrow(peps)),
               xlim = ranges$x,
               ylim = ranges$y,
               fcol = newName,
               mirrorX = mirrorX,
               mirrorY = mirrorY)
        if (!is.null(input$markers)) {
          for (i in 1:length(input$markers)) {
            if (!is.na(mrkSel()[[i]][1]))
              points(pcas[[2]][mrkSel()[[i]], ], pch = 16, 
                     cex = 1.4, col = myCols()[i])
          }
        }
        ## highlight point on plot by selecting item in table
        idDT <<- feats_pep[input$fDataTable_rows_selected]
        if (resetLabels$logical) idDT <<- character()  ## If TRUE labels are cleared
        if (length(idDT)) {
          ## ==== highlight all peps with the same protein group 
          protacc <- as.character(fData(peps)[idDT, groupBy])
          allpeps <- unlist(lapply(protacc, 
                                   function(z) 
                                     feats_pep[fData(peps)[, groupBy] == z]))
          pRoloc::highlightOnPlot(pcas[[2]], allpeps, cex = 1.3)
          ## === highlight selected pep as a solid circle
          pRoloc::highlightOnPlot(pcas[[2]], idDT, cex = 1.3)
          
          if (input$checkbox) {
            pRoloc::highlightOnPlot(pcas[[2]], idDT, labels = TRUE, pos = 3)
          }
          ## === highlight corresponding proteins on PCA plot
          pRoloc::highlightOnPlot(pcas[[1]], unique(protacc), cex = 2,
                          pch = 19, col = "black")
          pRoloc::highlightOnPlot(pcas[[1]], unique(protacc), cex = .8,
                          pch = 19, col = "red")
        }
        resetLabels$logical <<- FALSE
      })

       
      ## Protein profile plot
      output$profile2 <- renderPlot({
        par(mar = c(8, 3, 1, 1))
        par(oma = c(1, 0, 0, 0))
        ylim <- range(profs)
        n <- nrow(profs)
        m <- ncol(profs)
        fracs <- colnames(profs)
        plot(0, ylim = ylim, xlim = c(1, m), ylab = "Intensity", 
             type = "n", xaxt = "n", xlab = "")
        axis(1, at = 1:m, labels = fracs, las = 2)
        title(xlab = "Fractions", line = 5.5)
        matlines(t(profs[feats_pep, ]),
                 col = getUnknowncol(),
                 lty = 1,
                 type = "l")
        if (!is.null(input$markers)) {
          for (i in 1:length(input$markers)) { 
            if (!is.na(mrkSel()[[i]][1]))
              matlines(t(profs[mrkSel()[[i]], ]),
                       col = myCols()[i],
                       lty = 1,
                       lwd = 1.5)
          }
        }
        ## If an item is clicked in the table highlight profile
        idDT <<- feats_pep[input$fDataTable_rows_selected]
        if (length(idDT)) {
          ## Now add all peptides with the same protein group as
          ## dashed lines
          protacc <- as.character(fData(peps)[idDT, groupBy])
          allpeps <- unlist(lapply(protacc, 
                                   function(z) 
                                     feats_pep[fData(peps)[, groupBy] == z]))
          ## Plot peptides selected
          matlines(t(profs[allpeps, , drop = FALSE]),
                   col = "black",
                   lty = 3,
                   lwd = 1)
          matlines(t(profs[idDT, , drop = FALSE]),
                   col = "black",
                   lty = 1,
                   lwd = 2)        
        }
      })            
      
      
      ## Feature data table
      output$fDataTable <- DT::renderDataTable({
        
        feats_pep <<- featureNames(peps)
        feats_prot <<- rownames(protscatter())

        ## DOUBLE CLICK on AGGVAR PLOT to identify protein then
        ## calculate distance from point to find nearest
        if (!is.null(input$dblClickScatter)) {
          dist <- apply(protscatter()[, 1:2], 1, 
                        function(z) sqrt((input$dblClickScatter$x - z[1])^2
                                         + (input$dblClickScatter$y - z[2])^2))
          idPlot <- names(which(dist == min(dist)))
          indPep <- which(fData(peps)[, groupBy] == idPlot)
          idPlot <- featureNames(peps)[indPep]
          if (any(idPlot %in% idDT)) {                     ## 1--is it already clicked?
            idDT <<- setdiff(idDT, idPlot)                 ## Yes, remove it from table
          } else {                                         ## 2--new click?
            idDT <<- c(idDT, idPlot)                       ## Yes, highlight it to table
          }
        }
        
        ## DOUBLE CLICK on PCA PLOT to identify nearest peptide
        if (!is.null(input$dblClickPCA)) {
          dist <- apply(pcas[[2]], 1, 
                        function(z) sqrt((input$dblClickPCA$x - z[1])^2
                                         + (input$dblClickPCA$y - z[2])^2))
          idPlot <- names(which(dist == min(dist)))
          if (any(idPlot %in% idDT)) {                     ## 1--is it already clicked?
            idDT <<- setdiff(idDT, idPlot)                 ## Yes, remove it from table
          } else {                                         ## 2--new click?
            idDT <<- c(idDT, idPlot)                       ## Yes, highlight it to table
          }
        } 
        
        toSel <<- match(idDT, feats_pep)                    ## selection to highlight in DT
        if (resetLabels$logical) toSel <<- numeric()        ## reset labels
        if (resetLabels$logical) idDT <<- character()       ## reset labels
        
        dataDT <- fData(peps)[feats_pep, input$selTab, drop = FALSE]
        DT::datatable(data = dataDT, 
                      rownames = TRUE,
                      selection = list(mode = 'multiple', selected = toSel)
        )
      })
      
      
      ## When clear selection is pressed labels and reset selection 
      observeEvent(input$clear, {
        resetLabels$logical <<- TRUE
      })
      
      
      ## Output legend for pca
      output$legend1 <- renderPlot({
        par(mar = c(0, 0, 0, 0))
        par(oma = c(0, 0, 0, 0))
        plot(0, type = "n",
             xaxt = "n", yaxt = "n",
             xlab = "", ylab = "",
             bty = "n")
        if (!is.null(input$markers)) {
          legend("topleft",
                 c(input$markers, "unlabelled"),
                 col = c(substr(myCols(), 1, 7), getUnknowncol()),
                 ncol = 1, bty = "n",
                 
                 pch = c(rep(16, length(myCols())), 21),
                 cex = legend.cex)
        } else {
          legend("topleft",
                 "unlabelled",
                 col = getUnknowncol(),
                 ncol = 1, bty = "n",
                 pch = 21,
                 cex = legend.cex)
        }
      })
      
      
      ## Output legend for profiles
      output$legend2 <- renderPlot({
        par(mar = c(0, 0, 0, 0))
        par(oma = c(0, 0, 0, 0))
        plot(0, type = "n",
             xaxt = "n", yaxt = "n",
             xlab = "", ylab = "",
             bty = "n")
        if (!is.null(input$markers)) {
          legend("topleft",
                 c(input$markers, "unlabelled"),
                 col = c(substr(myCols(), 1, 7), getUnknowncol()),
                 ncol = 1, bty = "n",
                 pch = c(rep(16, length(myCols())), 21),
                 cex = legend.cex
          )
        } else {
          legend("topleft",
                 "unlabelled",
                 col = getUnknowncol(),
                 ncol = 1, bty = "n",
                 pch = 21,
                 cex = legend.cex)
        }
      })
      
    }
  app <- list(ui = ui, server = server)
  runApp(app)
}


## feats
##  features to display on PCA plot
##  profiles to diplay on matplot
##  features to show in DT::datatable

## feats[input$fDataTable_rows_selected]
##  features to highlight
##  feature selected in DT::datatable
