library(fda)
library(multicore)
library(MCMCpack)
library(coda)

source("R/load_data2.R")
source("R/smooth_corr.R")
source("R/spline_cov.R")

if (TRUE) {
	# let's subset the data...
	z <- z[,c(1,5,9)]

	#keep <- T <= 40
	#keep <- c(1, 1+sort( sample.int(nrow(z)-1, size=round(nrow(z)/8)) ))
	keep <- c(1, round(seq(2, nrow(z), len=round(nrow(z)/8))) )
	z <- z[keep,]; d <- d[keep]; f <- f[keep]; T <- T[keep]
}

# normalize the data
zstar <- sqrt(d) * z

# remove d_i = 0
rem <- which(d==0)
if (length(rem) > 0) {
	z <- z[-rem,]; d <- d[-rem]; f <- f[-rem]; T <- T[rem]; zstar <- zstar[-rem,]
}

n  <- nrow(zstar)
k  <- ncol(zstar)

"get_data" <- function(L) {
	if (L < 4) { stop("B-splines require L > 3\n") }

	# create basis functions
	Bbasis  <- create.bspline.basis(c(min(f),max(f)),norder=4,nbasis=L)
	knots   <- knots(Bbasis)
	weights <- getbasismatrix(f, Bbasis, nderiv=0)
	uf      <- quantile(f, seq(0,1,length=100))
	ufw     <- getbasismatrix(uf, Bbasis, nderiv=0)

	# capture which are non-zero
	nz <- apply(weights, 1, function(x){ which(x!=0) })

	# get number of non-zeros
	Nnz <- sapply(1:length(nz), function(i){ length(nz[[i]]) })

	# get non-zero indices
	Mnz <- matrix(0, nrow=length(nz), ncol=max(Nnz))
	sapply(1:length(nz), function(i){ Mnz[i,1:Nnz[i]] <<- nz[[i]] })

	# get non-zero weights
	Wnz <- matrix(0, nrow=length(nz), ncol=max(Nnz))
	sapply(1:length(nz), function(i){ Wnz[i,1:Nnz[i]] <<- weights[i,nz[[i]]] })

	data <- list(prior=1,
		n=n, k=k, y=zstar,
		L=L, weights=weights,
		Nnz=Nnz, Mnz=Mnz-1, Wnz=Wnz
	)

}

"get_starts" <- function(data) {
	# get initial values with BFGS
	init <- rep(0, data$L*(data$k+data$k*(data$k-1)/2))
	t1 <- proc.time()
	bfgs <- optim(par=init,
		fn=function(x) {
			lk <- spline_cov_lk(data=data, eval=x)$lk
			-lk
		},
		gr=function(x) {
			gr <- spline_cov_gr(data=data, eval=x)
			-gr
		},
	method="BFGS", control=list(maxit=5000))
	cat("Time to inits: (conv=",bfgs$conv,")\n",sep="")
	print(proc.time()-t1)

	bfgs
}

"do_fit" <- function(data, Niter=100, Nburn=50, step_e=0.01, step_L=1, starts) {
	# do we have starting values?
	if (missing(starts))
		has_starts <- FALSE
	else
		has_starts <- TRUE

	Nchains <- 3
	Ncores  <- 3
	Nparam <- data$L*(data$k + data$k*(data$k-1)/2)

	if (!has_starts) {
		init <- get_starts(data)$par
	} else {
		init <- starts
	}

	t1 <- proc.time()
	fits <- mclapply(1:Nchains, mc.cores=Ncores,
		function(i) {
		set.seed(311*i);
		fit <- spline_cov(data=data, step_e=ss, step_L=it, inits=init, Niter=Niter, verbose=TRUE)
	})

	# compute DIC

	# get samples, discarding burn
	sub <- -(1:Nburn)
	res <- vector("list", Nchains)
	dev <- vector("list", Nchains)
	for (i in 1:Nchains) {
		res[[i]] <- matrix(fits[[i]]$samples, nrow=Niter)[sub,]
		dev[[i]] <- matrix(fits[[i]]$deviance, nrow=Niter)[sub,]
	}

	# posterior mean
	pmean <- colMeans( do.call(rbind, res) )
	dmean <- mean( unlist(dev) )

	Dbar  <- dmean
	Dtbar <- -2*spline_cov_lk(prior=prior.sd, n=dat$n, k=dat$k, y=z, L=dat$L, Nnz=dat$Nnz, Mnz=dat$Mnz-1, Wnz=dat$Wnz, eval=pmean)$llik
	pD    <- Dbar - Dtbar
	DIC   <- Dbar + pD

	# save fit
	fname <- paste0("scL",L,"_",WHICH_CDAT,".RData")
	save(data$L, fits, res, init, DIC, pD, uf, ufw, knots, file=paste0("fitsums/fitsum_",fname))

	list(L=data$L, fits=fits, res=res, init=init, DIC=DIC, pD=pD)
}

#fit <- do_fit(0.05, 25) #, good_starts)
#fit <- do_fit(0.025, 5) #, good_starts)
#fit <- do_fit(0.025, 2^9) #, good_starts)

data5 <- get_data(5)
init5 <- get_starts(data5)

#fit1 <- do_fit(get_data(5), 0.025, 5) #, good_starts)
#fit2 <- do_fit(0.025, 10) #, good_starts)
#fit3 <- do_fit(0.025, 15) #, good_starts)
#fit4 <- do_fit(0.025, 20) #, good_starts)

#eps <- .0001; f1 <- do_fit(eps, 10*eps)
#eps <- .00001; f2 <- do_fit(eps, 10*eps)
#eps <- .000001; f3 <- do_fit(eps, 10*eps)
#eps <- .0000001; f4 <- do_fit(eps, 10*eps)
#eps <- .0001; f1 <- do_fit(eps, 10*eps)
#eps <- .0001; f2 <- do_fit(eps, 50*eps)
#eps <- .0001; f3 <- do_fit(eps, 100*eps)
#eps <- .0001; f4 <- do_fit(eps, 150*eps)
#eps <- .0001; f5 <- do_fit(eps, 200*eps)
#eps <- .0001; f6 <- do_fit(eps, 250*eps)
#eps <- .0001; f7 <- do_fit(eps, 512*eps)
#eps <- .0001; f8 <- do_fit(eps, 1024*eps)
#eps <- .0001; fs <- do_fit(eps, 1024*eps)

#round(sapply(1:nrow(ufw),function(i){ 2*invlogit( sum(v3*ufw[i,]) )-1 }),2)
