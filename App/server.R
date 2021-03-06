palette(c("#E41A1C", "#377EB8", "#4DAF4A", "#984EA3",
          "#FF7F00", "#FFFF33", "#A65628", "#F781BF", "#999999"))
options(shiny.maxRequestSize = 15*1024^2) #server file input limit (15MB)
shinyServer(function(input, output, session) {
  source("functions.R")
  #############################
  # DATA INPUT + MANIPULATION #
  #############################
  
  tbl<-reactive({ #tbl()=user input or sample iris data
    inFile <- input$file1
    if (is.null(inFile)) {
      return(iris)
    }
    else{
      csv<-read.csv(inFile$datapath, header=input$header, sep=input$sep, quote=input$quote)  
      csv <- csv[,colSums(is.na(csv))<nrow(csv)] #remove columns with all NAs
      csv<-na.omit(csv) #omit N/A values
      return(csv)
    }
  })
  
  
  # EXPORT DATA TO TABLE
  output$mydata <- DT::renderDataTable({
    return (tbl())
  },extensions = 'TableTools',options = list(searchHighlight=TRUE,rownames=FALSE,
      "sDom" = 'T<"clear">lfrtip',"oTableTools" = list("sSwfPath" = "//cdnjs.cloudflare.com/ajax/libs/datatables-tabletools/2.1.5/swf/copy_csv_xls.swf",
      "aButtons" = list("copy","print",list("sExtends" = "collection","sButtonText" = "Save","aButtons" = c("csv","xls")))
    )
  ))
  
  output$summary<-renderPrint({summary(tbl())})

  #################
  # VISUALIZATION #
  #################
  rplot <- reactiveValues(x = NULL, y = NULL)
  # BOXPLOTS
  output$vis <- renderUI({
    numeric <- sapply(tbl(), is.numeric)
    selectInput("vis", "Choose Column(s)", names(tbl()[numeric]), multiple=TRUE, selected=list(names(tbl()[numeric])[[1]],names(tbl()[numeric])[[2]]))
  })
  output$groupcol <- renderUI({
    categorical <- !sapply(tbl(), is.numeric) #only group by categorical fields
    selectizeInput(
      'groupcol', 'Group By', choices = names(tbl()[categorical]),
      multiple = TRUE, options = list(maxItems = 1)
    )
  })
  
  bplot = function() {
    b<-tbl()[input$vis]
    boxplot(b)
  }
  output$boxplot<-renderPlot({print(bplot())})
  
  # DENSITY GRAPH
  dplot = function() {
    mdat<-melt(tbl()[input$vis])
    ggplot(mdat, aes(value)) +
      geom_histogram(aes(y=..density..), binwidth=5, colour='black', fill='skyblue') + 
      geom_density() + 
      facet_wrap(~variable, scales="free")+
      coord_cartesian(xlim = rplot$x, ylim = rplot$y)
  }
  output$densityplot<-renderPlot({print(dplot())})
  observeEvent(input$plotdblclick, { #Dynamic range (drag and double click to resize graph)
    brush <- input$brush
    if (!is.null(brush)) {
      rplot$x <- c(brush$xmin, brush$xmax)
      rplot$y <- c(brush$ymin, brush$ymax)
      
    } else {
      rplot$x <- NULL
      rplot$y <- NULL
    }
  })
  
  # SCATTERPLOT
  splot = function() {
    if(is.null(input$groupcol)){
      plot(tbl()[input$vis])  
    }
    else{
      plot(tbl()[input$vis],col=tbl()[[input$groupcol]]) 
      legend ("topleft", legend = levels(tbl()[[input$groupcol]]), col = c(1:3), pch = 16)
    }
   
  }
  output$scatterplot<-renderPlot({print(splot())})
  
  #################
  #    MODELING   #
  #################
  
  # K-MEANS CLUSTERING
  output$clust_indep <- renderUI({
    numeric <- sapply(tbl(), is.numeric)
    selectInput("clust_indep", "Independent Variable", names(tbl()[numeric]), multiple=FALSE, selected=list(names(tbl()[numeric])[[2]]))
  })
  output$clust_dep <- renderUI({
    numeric <- sapply(tbl(), is.numeric)
    selectInput("clust_dep", "Dependent Variable", names(tbl()[numeric]), multiple=FALSE, selected=list(names(tbl()[numeric])[[1]]))
  })
  selectedData <- reactive({
    
    if(is.null(input$clust_dep)){
      tbl()[,c(names(tbl()[numeric])[[2]],names(tbl()[numeric])[[1]])]
    }
    tbl()[, c(input$clust_dep, input$clust_indep)]
  })
  clusters <- reactive({kmeans(selectedData(), input$clusters)})
  kplot=function(){
    par(mar = c(5.1, 4.1, 0, 1))
    plot(selectedData(), col = clusters()$cluster, pch = 20, cex = 3)
    points(clusters()$centers, pch = 4, cex = 4, lwd = 4)
  }
  output$model1<-renderPlot({print(kplot())})
  output$model1_info<-renderPrint({
    print(clusters())
  })
  onclick("model1",toggle("model1_i", anim=TRUE))
  
  # BIVARIATE LINEAR REGRESSION
  output$lm_indep <- renderUI({
    numeric <- sapply(tbl(), is.numeric)
    selectInput("lm_indep", "Independent Variable", names(tbl()[numeric]), multiple=FALSE, selected=list(names(tbl()[numeric])[[2]]))
  })
  output$lm_dep <- renderUI({
    numeric <- sapply(tbl(), is.numeric)
    selectInput("lm_dep", "Dependent Variable", names(tbl()[numeric]), multiple=FALSE, selected=list(names(tbl()[numeric])[[1]]))
  })
  lmplot=function(){
    fit<-lm(as.formula(paste(input$lm_dep," ~ ",paste(input$lm_indep))),data=tbl())
    ggplot(fit$model, aes_string(x = names(fit$model)[2], y = names(fit$model)[1])) + 
      geom_point() +
      stat_smooth(method = "lm", col = "red") +
      labs(title = paste("y =",signif(fit$coef[[2]], 5),"x + ",signif(fit$coef[[1]],5 )))
    
  }
  output$model2<-renderPlot({print(lmplot())})
  output$model2_info<-renderPrint({
    mod<-lm(as.formula(paste(input$lm_dep," ~ ",paste(input$lm_indep))),data=tbl())
    print(summary(mod))
  })
  output$model2_resid<-renderPlot({
    mod<-lm(as.formula(paste(input$lm_dep," ~ ",paste(input$lm_indep))),data=tbl())
    plot(resid(mod))
    abline(0,0, col="red")
  })
  onclick("model2",toggle("model2_i", anim=TRUE))
  
  # Decision Tree
  output$tree_indep <- renderUI({
    selectInput("tree_indep", "Independent Variable(s)", names(tbl()[ , names(tbl()) != input$tree_dep]), multiple=TRUE, selected=list(names(tbl()[ , names(tbl()) != input$tree_dep])[[2]]))
  })
  output$tree_dep <- renderUI({
    selectInput("tree_dep", "Dependent Variable", names(tbl()), multiple=FALSE, selected=list(names(tbl())[[1]]))
  })
  dtplot=function(){
    stree = ctree(as.formula(paste(input$tree_dep," ~ ",paste(input$tree_indep,collapse="+"))), data = tbl())
    plot(stree)
  }
  output$model3<-renderPlot({print(dtplot())})
  output$model3_info<-renderPrint({
    stree = ctree(as.formula(paste(input$tree_dep," ~ ",paste(input$tree_indep,collapse="+"))), data = tbl())
    print(stree)
  })
  onclick("model3",toggle("model3_i", anim=TRUE))

  
  #########################################
  #            SAVE PLOT(S)               #
  #########################################
  output$downloadPlots <- downloadHandler( filename = "Report.pdf",content = function(file) {
    pdf(file) 
    for (i in 1:length(input$plots)){
      if(input$plots[i]=="Boxplot")
        print(bplot())
      if(input$plots[i]=="Density Plot")
        print(dplot())
      if(input$plots[i]=="Scatter Plot")
        print(splot())
      if(input$plots[i]=="K-Means")
        print(kplot())
      if(input$plots[i]=="Linear Model")
        print(lmplot())
      if(input$plots[i]=="Decision Tree")
        print(dtplot())
    }
    dev.off()})
  
})                 